# Gcp_Managed_GKE_GIT_ETC_10 — gcloud version

This repository is the **gcloud / kubectl implementation** of `sonmap/Gcp_Managed_GKE_GIT_ETC_09`, whose infrastructure layer is Terraform-based.

## Design retained from ETC_09

- CI/CD project: `prj-b-cicd-local-236d`
- Main GKE project: `pjt-d-host01`
- Shared VPC host: `pjt-d-shared-base`
- Shared VPC: `vpc-d-shared-base`
- Region: `asia-northeast3`
- Main GKE Autopilot Pod range: `10.240.0.0/20`
- Main control plane: `10.253.0.0/28`
- Test GKE Pod range: `10.240.32.0/22`
- Test control plane: `10.253.0.16/28`
- Cloud Build PSA: `10.250.0.0/24`
- Cloud Run Direct VPC egress subnet: `10.251.0.0/26`
- Internal ALB frontend: `172.31.104.0/29`, VIP `172.31.104.4`
- Regional managed proxy-only subnet: `10.254.0.0/26`
- Sandbox example: `sbx01`

## Execution

```bash
git clone https://github.com/sonmap/https-github.com-sonmap-Gcp_Managed_GKE_GIT_ETC_10.git
cd https-github.com-sonmap-Gcp_Managed_GKE_GIT_ETC_10

chmod +x *.sh
source ./config.env

gcloud auth login
gcloud config set compute/region asia-northeast3

# 1. Shared VPC host resources
./01-network.sh

# 2. Foundation resources: APIs, Artifact Registry, GKE Autopilot
./02-foundation.sh

# 3. sbx01 data + Workload Identity + namespace/KSA
./03-sandbox-sbx01.sh
```

## Terraform -> CLI mapping

| ETC_09 Terraform | ETC_10 CLI |
|---|---|
| `google_compute_subnetwork` | `gcloud compute networks subnets create` |
| `google_compute_address` | `gcloud compute addresses create` |
| `google_compute_global_address` PSA | `gcloud compute addresses create --global --purpose=VPC_PEERING` |
| `google_service_networking_connection` | `gcloud services vpc-peerings connect` |
| `google_project_service` | `gcloud services enable` |
| `google_artifact_registry_repository` | `gcloud artifacts repositories create` |
| `google_container_cluster` Autopilot | `gcloud container clusters create-auto` |
| `google_service_account` | `gcloud iam service-accounts create` |
| Project IAM | `gcloud projects add-iam-policy-binding` |
| GCS | `gcloud storage buckets ...` |
| BigQuery dataset | `bq mk` + `bq add-iam-policy-binding` |
| GKE namespace/KSA | `kubectl create/apply/annotate` |

## Important

The scripts are deliberately **idempotency-oriented**: existing subnets, IPs, clusters, service accounts, buckets, datasets, and repositories are checked before creation where practical. IAM bindings are additive.

ETC_09 also contains Cloud Build Private Pool, Cloud Run provisioner, Workflow orchestration, JupyterHub/Helm, and Internal ALB workload-specific definitions. These should be converted next into separate `04-cloudbuild.sh`, `05-cloudrun-workflow.sh`, `06-jupyterhub.sh`, and `07-ilb.sh` stages rather than mixing them into the foundation script. This keeps the same two-stage operational boundary used by ETC_09 while removing Terraform state dependency.
