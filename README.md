# Kubernetes Bootstrap ArgoCD

## How to run the project

1) Install dependencies with [Mise](https://mise.jdx.dev/)

```sh
mise install
```

2) Adjust backend and vars file in `config/dev/us-east-1.tfvars` folder

3) Export AWS credentials related to the account you would like to deploy

4) Initialize Terraform

```sh
cd src/
mise run init-dev
```

5) Deploy initial infrastructure

```sh
mise run apply-dev-bootstrap
```

The infrastructure needs to be deployed in a two-phase process when using Terraform. This is a limitation of the Kubernetes provider for Terraform, since it's required to have an [EKS cluster provisioned before using the provider](https://registry.terraform.io/providers/hashicorp/kubernetes/3.0.1/docs#stacking-with-managed-kubernetes-cluster-resources).


6) Deploy the rest of the infrastructure

```sh
mise run apply-dev
```

From now on, no need to run bootstrap anymore! Every future deployment can run directly `mise run apply-dev`.

7) Add Deploy key to GitHub Repository

The Terraform created the SSH key to be used by ArgoCD in order to pull the repository (if it's private). Basically you should copy the output of `argocd_deploy_public_key` and add it as a `Deploy Key` in your repository.
