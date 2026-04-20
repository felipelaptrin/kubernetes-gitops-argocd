---
name: new-argocd-app
description: Scaffold a new ArgoCD ApplicationSet in this repository following the GitOps Bridge Pattern with MERGE generator strategy. Use when the user wants to add a new addon or application to the cluster.
---

# New ArgoCD Application Scaffold

You are helping the user add a new ArgoCD Application to this repository. This repo uses the **GitOps Bridge Pattern**: Terraform creates a Kubernetes Secret (the ArgoCD cluster secret) with infrastructure annotations, and ApplicationSets consume those annotations to render Applications dynamically per environment.

## Repository Structure Recap

```
k8s/
├── addons/          ← ApplicationSet YAML files for infra tools (helm/kustomize)
├── apps/            ← ApplicationSet YAML files for user workloads (helm/kustomize)
├── bootstrap/       ← Bootstrap-ApplicationSets for App-of-Apps pattern (do not touch unless bootstrapping)
└── environments/
    ├── default/     ← Shared Helm values / Kustomize bases (all envs)
    │   ├── addons/<addon-name>/values.yaml   (Helm)
    │   └── addons/<addon-name>/kustomization.yaml + manifests  (Kustomize)
    └── dev/         ← Dev-specific overrides
        └── addons/<addon-name>/values.yaml (Helm) to override or .gitkeep (inherit default)
        └── addons/<addon-name>/kustomization.yaml + manifests (Kustomize) to override (point to k8s/environments/default/<addon-name>)
```

## Available Cluster Annotations (from GitOps Bridge)

These are injected into every ApplicationSet template via `{{ metadata.annotations.<key> }}`

Check Terraform resource "kubernetes_secret_v1.argocd_cluster" on file src/k8s.tf file to see the available values.

Template values set per-generator (not annotations) are accessed via `{{ values.<key> }}`.

## Step 1 — Gather Requirements

Ask the user the following questions **all at once** (do not ask one by one):

1. **Type**: Is this an `addon` (infrastructure tool like a controller or operator) or an `app` (user workload)?
2. **Name**: What is the ApplicationSet/addon name? (e.g. `cert-manager`) — this becomes the filename in `k8s/addons/` or `k8s/apps/`
3. **Deployment method**: Does it use `helm` or `kustomize`?
4. **Namespace**: Which Kubernetes namespace should it deploy to?
5. **Expose**: Does the application should be exposed via Gateway API? If so, what's the subdomain?

If the new application is of type `helm` you should check the widely-used Helm Chart repository, version and the recommended namespace to deploy and ask the user if these values are ok. If not, ask the user what chart name, URL, version and namespace to use.

## Step 2 — Generate Files

Based on the answers, create the following files:

---

### File 1: ApplicationSet (`k8s/addons/<name>.yaml` or `k8s/apps/<name>.yaml`)

#### Helm variant (MERGE generator — deploy to all envs with env-specific overrides):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: <name>
  namespace: argocd
  # Add only if sync wave is needed:
  # annotations:
  #   argocd.argoproj.io/sync-wave: "<wave-number>"
spec:
  generators:
    - merge:
        mergeKeys: [name]
        generators:
          # Generator 1: matches ALL clusters that have the "environment" label.
          # Sets default chart name and version used across all environments.
          - clusters:
              selector:
                matchExpressions:
                  - key: environment
                    operator: Exists
              values:
                chart: <chart-name>
                chartVersion: <chart-version>
          # Generator 2+: one per environment. Currently empty (no value overrides),
          # but required for the MERGE pattern to work and allows future per-env overrides.
          - clusters:
              selector:
                matchLabels:
                  environment: dev
  template:
    metadata:
      name: "{{ metadata.annotations.environment }}-{{ values.chart }}"
      # Add if sync wave needed:
      # annotations:
      #   argocd.argoproj.io/sync-wave: "<wave-number>"
    spec:
      project: default
      sources:
        - repoURL: <helm-repo-url>
          chart: '{{ values.chart }}'
          targetRevision: '{{ values.chartVersion }}'
          helm:
            ignoreMissingValueFiles: true
            valueFiles:
              - $values/k8s/environments/default/addons/{{ values.chart }}/values.yaml
              - $values/k8s/environments/{{ metadata.annotations.environment }}/addons/{{ values.chart }}/values.yaml
            # Include only if dynamic annotation values are needed:
            # values: |
            #   someHelmKey: "{{ metadata.annotations.cluster_name }}"
            #   anotherKey: "{{ metadata.annotations.aws_region }}"
        - repoURL: '{{ metadata.annotations.gitops_repo_url }}'
          targetRevision: "{{ metadata.annotations.gitops_repo_revision }}"
          ref: values
      destination:
        name: "{{ name }}"
        namespace: <namespace>
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
```

---

### File 2: Default environment values

**Helm:** `k8s/environments/default/addons/<chart-name>/values.yaml`
- Include only values that override chart defaults and apply to all environments.
- If no overrides are needed, create an empty file (not `.gitkeep` — Helm needs a real YAML file, even if empty).

**Kustomize (base):** `k8s/environments/default/addons/<name>/kustomization.yaml` + manifest files
- Create the base Kustomize manifest(s) here.

---

### File 3: Environment-specific files

For each environment (currently only `dev`):

**Helm:**
- If the env has overrides: `k8s/environments/dev/addons/<chart-name>/values.yaml` with the override values.
- If the env inherits defaults: `k8s/environments/dev/addons/<chart-name>/.gitkeep` (empty placeholder — `ignoreMissingValueFiles: true` means the missing values.yaml is fine, but the directory should exist).

**Kustomize:**
- `k8s/environments/dev/addons/<name>/kustomization.yaml` referencing the default base:
  ```yaml
  apiVersion: kustomize.config.k8s.io/v1beta1
  kind: Kustomization
  resources:
    - ../../../default/addons/<name>
  ```

---

## Step 3 — Summary

After creating the files, tell the user:
1. Which files were created and their paths.
2. Remind them that the ApplicationSet will be picked up automatically by the `addons` (or `apps`) meta-ApplicationSet in `k8s/bootstrap/addons-app.yaml` — no other wiring is needed.
3. If they need to add IRSA (IAM Role for Service Account) for the addon, that must be done in Terraform (`src/` directory) — point them there.
4. If they added a sync wave, remind them about the dependency ordering relative to other addons.
