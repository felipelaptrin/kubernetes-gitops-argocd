# Kubernetes Bootstrap with ArgoCD

## Problem

When provisioning infrastructure with Terraform, the outputs (VPC IDs, IAM role ARNs, certificate
ARNs, cluster endpoints, queue URLs, etc.) need to be consumed by Kubernetes workloads. These
workloads are managed via GitOps, which means their configuration lives in a Git repository as
static YAML. The challenge is: **how do dynamic, runtime infrastructure values flow into
GitOps-managed Helm charts and manifests without hardcoding them in Git?**

This becomes especially concrete with addons like:
- **AWS Load Balancer Controller** — requires the VPC ID as a command argument
- **Karpenter** — requires the cluster name, SQS queue URL, and IAM role ARN
- **External DNS** — requires the IAM role ARN
- **cert-manager** — may require the Route53 hosted zone ID

These values are unknowable before `terraform apply` runs. They can't be static in Git, and they
shouldn't be treated as secrets (they aren't sensitive). The naive solution — committing
Terraform outputs directly to the Git repository as generated files — pollutes the repo with
machine-generated content and tightly couples infrastructure execution to repository write access.

---

## Goal

A production-grade GitOps setup on AWS EKS where:

1. Terraform provisions all AWS infrastructure and bootstraps ArgoCD
2. ArgoCD manages all cluster addons and workloads via GitOps
3. Dynamic infrastructure values flow cleanly from Terraform into Helm chart configurations
4. Sensitive values (passwords, tokens) never touch Git
5. Addons deploy in the correct dependency order
6. ArgoCD manages its own configuration and upgrades (self-managed)
7. The Git repository contains only human-authored, reviewable content — no generated artifacts

---

## Proposed Solution

### Overview

The solution uses three mechanisms working together:

| Concern | Mechanism |
|---|---|
| ArgoCD installation | Terraform `helm_release` |
| Non-sensitive infra values (VPC ID, ARNs, etc.) | GitOps Bridge — cluster Secret annotations read by ApplicationSet Cluster generator |
| Fixed non-sensitive values (replicas, resource limits, feature flags) | `values.yaml` files committed to Git |
| Sensitive values (passwords, tokens) | External Secrets Operator + AWS Secrets Manager |
| Addon dependency ordering | ArgoCD sync waves |
| ArgoCD self-management | Self-referential ArgoCD Application in Git |

---

### 1. ArgoCD Bootstrap

Terraform is responsible for the initial cluster setup. This is a one-time operation that
establishes the GitOps foundation.

**Steps:**

1. Terraform provisions the EKS cluster
2. Terraform creates namespaces for all addons upfront — this avoids race conditions where
   ArgoCD tries to create a namespace at the same moment an operator needs it to already exist
3. Terraform installs ArgoCD via `helm_release` using the official `argo-cd` Helm chart
4. Terraform creates the **cluster Secret** with infrastructure annotations (see section 2)
5. Terraform applies a single root `Application` manifest pointing to `k8s/bootstrap/` in Git

From this point, ArgoCD takes over. Terraform's job is done until infrastructure changes.

```hcl
# src/k8s.tf (sketch)

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  values           = [file("${path.module}/helm-values/argocd.yaml")]
  wait             = true  # ensure ArgoCD is up before creating Applications
}

resource "kubernetes_manifest" "root_app" {
  depends_on = [helm_release.argocd]
  manifest   = yamldecode(file("${path.module}/bootstrap/root-app.yaml"))
}
```

**Two-phase Terraform apply** (avoids provider chicken-and-egg issues):
```
Phase 1: terraform apply -target=module.vpc -target=module.eks
Phase 2: terraform apply   # installs ArgoCD, creates cluster Secret, applies root app
```

---

### 2. Passing Non-Sensitive Infrastructure Values — GitOps Bridge

This is the core pattern that solves the IaC-to-GitOps value gap.

#### How it works

**Terraform annotates the ArgoCD cluster Secret** with all infrastructure outputs that addons
need:

```hcl
# src/k8s.tf
resource "kubernetes_secret" "argocd_cluster" {
  metadata {
    name      = "in-cluster"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "environment"                     = var.environment
    }
    annotations = {
      "infra/vpc-id"           = module.vpc.vpc_id
      "infra/aws-region"       = var.aws_region
      "infra/aws-account-id"   = data.aws_caller_identity.current.account_id
      "infra/cluster-name"     = module.eks.cluster_name
      "infra/acm-cert-arn"     = module.acm.certificate_arn
      "infra/karpenter-queue"  = module.karpenter.queue_name
      # ... one annotation per Terraform output that addons need
    }
  }
  data = {
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } })
  }
}
```

**ApplicationSets in Git use the Cluster generator** to read those annotations as template
variables. Each ApplicationSet generates an Application per matching cluster:

```yaml
# k8s/addons/applicationsets/alb-controller.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: alb-controller
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            environment: dev   # matches the label Terraform set on the cluster Secret
  template:
    metadata:
      name: "alb-controller"
      annotations:
        argocd.argoproj.io/sync-wave: "5"
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/kubernetes-bootstrap-argocd
        targetRevision: main
        path: k8s/addons/alb-controller
        helm:
          valueFiles:
            - values.yaml   # static values from Git
          values: |         # dynamic values from cluster annotations
            vpcId: "{{ metadata.annotations['infra/vpc-id'] }}"
            clusterName: "{{ metadata.annotations['infra/cluster-name'] }}"
            region: "{{ metadata.annotations['infra/aws-region'] }}"
      destination:
        server: "{{ server }}"
        namespace: alb-controller
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - ServerSideApply=true
```

**Why this is clean:**
- The Git repository contains only static, human-authored YAML
- No generated files, no Terraform commits to the repo
- Terraform does not need Git write access
- Infrastructure values update automatically: Terraform runs → updates cluster Secret
  annotations → ApplicationSet re-renders → ArgoCD syncs updated values

---

### 3. Passing Fixed Non-Sensitive Values

Static configuration that doesn't vary by infrastructure state is committed to Git as
`values.yaml` files alongside each addon:

```
k8s/addons/alb-controller/
├── values.yaml          # chart version, resource limits, log level, feature flags
```

These files are human-authored, code-reviewed, and version-controlled. They complement the
dynamic values injected via the ApplicationSet template.

---

### 4. Passing Sensitive Values — External Secrets Operator

Sensitive values (database passwords, API tokens, webhook secrets) follow a different path:

```
Terraform → AWS Secrets Manager → ESO → Kubernetes Secret → Pod
```

**Step 1 — Terraform stores the secret:**
```hcl
resource "aws_secretsmanager_secret_version" "rds" {
  secret_id     = aws_secretsmanager_secret.rds.id
  secret_string = jsonencode({
    host     = module.rds.db_instance_endpoint
    port     = 5432
    username = module.rds.db_instance_username
    password = module.rds.db_instance_password
  })
}
```

**Step 2 — ESO is installed as an addon** (via its own ApplicationSet) and configured with
an IAM role (IRSA) that grants read access to Secrets Manager. The role ARN flows via the
cluster annotation pattern described above.

**Step 3 — A `ClusterSecretStore` in Git** defines the AWS Secrets Manager connection (no
credentials — authentication is handled by the IRSA token on the ESO pod):

```yaml
# k8s/addons/external-secrets/cluster-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

**Step 4 — `ExternalSecret` CRs in Git** declare which secrets to sync and under what names:

```yaml
# k8s/addons/my-app/external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: rds-credentials
  namespace: my-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: rds-credentials   # name of the resulting K8s Secret
    creationPolicy: Owner
  data:
    - secretKey: host
      remoteRef:
        key: /dev/rds/my-app
        property: host
    - secretKey: password
      remoteRef:
        key: /dev/rds/my-app
        property: password
```

The application references the resulting Kubernetes Secret by name. Sensitive values never
appear in Git at any point.

---

### 5. Dependency Ordering — Sync Waves

ArgoCD does not have native `dependsOn` between Applications. Sync waves fill this role:
resources in wave N must all be healthy before wave N+1 starts.

Waves are set as annotations on Application/ApplicationSet manifests:

| Wave | What | Reason |
|------|------|--------|
| `-10` | CRD-only Applications (Karpenter CRDs, Gateway API CRDs) | CRDs must exist before any CR is applied |
| `-5` | External Secrets Operator | Must be running before any ExternalSecret is reconciled |
| `0` | Karpenter, cert-manager | Core cluster infrastructure |
| `5` | AWS Load Balancer Controller, External DNS | Require nodes and IAM to be ready |
| `10` | General addons (Istio, monitoring, ingress) | Depend on ALB and DNS being functional |
| `20` | Application workloads | Depend on all platform addons |

Additionally, for addons that install CRDs alongside their own custom resources, set:
```yaml
syncOptions:
  - SkipDryRunOnMissingResource=true
```
This prevents ArgoCD's dry-run from failing when it encounters a CRD that doesn't exist yet.

---

### 6. ArgoCD Self-Management

ArgoCD manages its own Helm values via a self-referential Application in Git. Any change
to ArgoCD's configuration (RBAC, notifications, resource exclusions, plugin config) is made
by editing a file in Git and pushing — ArgoCD then applies the change to itself.

```yaml
# k8s/bootstrap/argocd-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argocd
spec:
  project: default
  sources:
    - repoURL: https://argoproj.github.io/argo-helm
      chart: argo-cd
      targetRevision: "7.x.x"
      helm:
        valueFiles:
          - $values/k8s/bootstrap/argocd-values.yaml
    - repoURL: https://github.com/your-org/kubernetes-bootstrap-argocd
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

### 7. Repository Structure

```
kubernetes-bootstrap-argocd/
│
├── src/                              # Terraform
│   ├── main.tf                       # VPC, EKS
│   ├── k8s.tf                        # ArgoCD bootstrap, cluster Secret, namespaces
│   ├── iam.tf                        # IRSA roles (ESO, Karpenter, ALB, ExternalDNS)
│   ├── secrets.tf                    # AWS Secrets Manager entries
│   ├── variables.tf
│   ├── locals.tf
│   ├── providers.tf
│   ├── versions.tf
│   ├── helm-values/
│   │   └── argocd.yaml               # ArgoCD Helm values for initial bootstrap
│   └── bootstrap/
│       └── root-app.yaml             # Root Application (applied once by Terraform)
│
├── k8s/
│   ├── bootstrap/                    # ArgoCD self-management
│   │   ├── argocd-app.yaml           # ArgoCD manages itself
│   │   └── argocd-values.yaml        # ArgoCD Helm values (RBAC, repos, notifications)
│   │
│   └── addons/
│       ├── applicationsets/          # One ApplicationSet per addon
│       │   ├── crds.yaml             # wave: -10
│       │   ├── external-secrets.yaml # wave: -5
│       │   ├── karpenter.yaml        # wave: 0
│       │   ├── cert-manager.yaml     # wave: 0
│       │   ├── alb-controller.yaml   # wave: 5
│       │   ├── external-dns.yaml     # wave: 5
│       │   └── ...
│       │
│       ├── crds/                     # CRD-only manifests (no controllers)
│       │   ├── karpenter/
│       │   └── gateway-api/
│       │
│       ├── external-secrets/
│       │   ├── values.yaml
│       │   └── cluster-secret-store.yaml
│       │
│       ├── karpenter/
│       │   └── values.yaml           # Static: tolerations, resource limits, log level
│       │
│       ├── alb-controller/
│       │   └── values.yaml           # Static: image, resources, podDisruptionBudget
│       │
│       └── <addon>/
│           ├── values.yaml
│           └── external-secret.yaml  # Present only if addon needs secrets
│
└── config/
    └── dev/
        ├── terraform.tfvars
        └── backend.hcl
```

---

### 8. Value Flow Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│ TERRAFORM                                                           │
│                                                                     │
│  module.vpc.vpc_id ──────────────────────────────────────────────┐ │
│  module.eks.cluster_name ────────────────────────────────────────┤ │
│  module.acm.certificate_arn ─────────────────────────────────────┤ │
│  module.karpenter.queue_name ────────────────────────────────────┤ │
│                                                                   ▼ │
│                                              ArgoCD cluster Secret  │
│                                              (annotations)          │
│                                                                     │
│  module.rds.password ────────────────► AWS Secrets Manager         │
└─────────────────────────────────────────────────────────────────────┘
                         │                         │
                         ▼                         ▼
              ApplicationSet               External Secrets
              Cluster generator            Operator
                         │                         │
                         ▼                         ▼
              helm.values inline          Kubernetes Secret
              (non-sensitive)             (sensitive)
                         │                         │
                         └───────────┬─────────────┘
                                     ▼
                              Pod / Helm chart
```

---

### 9. Key Design Decisions

- **Namespaces created by Terraform**, not ArgoCD — avoids first-sync race conditions
- **Terraform never writes to the Git repository** — clean separation of concerns
- **No generated files in Git** — every file is human-authored and reviewable
- **CRDs deployed separately** from their controllers — prevents sync failures on first install
- **`selfHeal: true` on all addons** — ArgoCD continuously reconciles back to Git state
- **IRSA for all AWS integrations** — no static credentials anywhere in the cluster
