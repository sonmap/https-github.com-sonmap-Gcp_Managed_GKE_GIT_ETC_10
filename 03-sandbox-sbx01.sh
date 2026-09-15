#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.env"

# APIs for the existing task project
gcloud services enable bigquery.googleapis.com storage.googleapis.com iam.googleapis.com --project="$TASK_PROJECT"

GSA="gsa-jupyter-${TASK}"
GSA_EMAIL="${GSA}@${TASK_PROJECT}.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe "$GSA_EMAIL" --project="$TASK_PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$GSA" --project="$TASK_PROJECT" --display-name="Jupyter ${TASK}"
fi

# BigQuery dataset
if ! bq --project_id="$TASK_PROJECT" show "${TASK_PROJECT}:${BQ_DATASET}" >/dev/null 2>&1; then
  bq --project_id="$TASK_PROJECT" --location="$REGION" mk --dataset "${TASK_PROJECT}:${BQ_DATASET}"
fi
bq add-iam-policy-binding --member="group:${TASK_GROUP}" --role=roles/bigquery.dataEditor "${TASK_PROJECT}:${BQ_DATASET}"
bq add-iam-policy-binding --member="serviceAccount:${GSA_EMAIL}" --role=roles/bigquery.dataEditor "${TASK_PROJECT}:${BQ_DATASET}"
gcloud projects add-iam-policy-binding "$TASK_PROJECT" --member="serviceAccount:${GSA_EMAIL}" --role=roles/bigquery.jobUser --quiet

# GCS
if ! gcloud storage buckets describe "gs://${GCS_BUCKET}" --project="$TASK_PROJECT" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${GCS_BUCKET}" --project="$TASK_PROJECT" --location="$REGION" --uniform-bucket-level-access --public-access-prevention
  gcloud storage buckets update "gs://${GCS_BUCKET}" --versioning
fi
gcloud storage buckets add-iam-policy-binding "gs://${GCS_BUCKET}" --member="group:${TASK_GROUP}" --role=roles/storage.objectUser
 gcloud storage buckets add-iam-policy-binding "gs://${GCS_BUCKET}" --member="serviceAccount:${GSA_EMAIL}" --role=roles/storage.objectUser

# Workload Identity: GKE KSA -> task-project GSA
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" --project="$TASK_PROJECT" --role=roles/iam.workloadIdentityUser --member="serviceAccount:${GKE_PROJECT}.svc.id.goog[${GKE_NAMESPACE}/${KSA}]"

# Kubernetes namespace/KSA. Run from a host that can reach the private GKE control plane.
gcloud container clusters get-credentials "$GKE_MAIN_CLUSTER" --region="$REGION" --project="$GKE_PROJECT"
kubectl create namespace "$GKE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount "$KSA" -n "$GKE_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl annotate serviceaccount "$KSA" -n "$GKE_NAMESPACE" "iam.gke.io/gcp-service-account=${GSA_EMAIL}" --overwrite

echo "[OK] ${TASK} data/IAM/KSA stage complete"
