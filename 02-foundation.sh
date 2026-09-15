#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.env"

CICD_APIS=(cloudbuild.googleapis.com run.googleapis.com artifactregistry.googleapis.com workflows.googleapis.com workflowexecutions.googleapis.com container.googleapis.com secretmanager.googleapis.com iam.googleapis.com servicenetworking.googleapis.com)
GKE_APIS=(container.googleapis.com iam.googleapis.com logging.googleapis.com monitoring.googleapis.com)

gcloud services enable "${CICD_APIS[@]}" --project="$CICD_PROJECT"
gcloud services enable "${GKE_APIS[@]}" --project="$GKE_PROJECT"

# Artifact Registry
if ! gcloud artifacts repositories describe cicd-images --location="$REGION" --project="$CICD_PROJECT" >/dev/null 2>&1; then
  gcloud artifacts repositories create cicd-images --repository-format=docker --location="$REGION" --project="$CICD_PROJECT" --description='CI/CD container images'
fi

# Main private Autopilot cluster on Shared VPC
if ! gcloud container clusters describe "$GKE_MAIN_CLUSTER" --region="$REGION" --project="$GKE_PROJECT" >/dev/null 2>&1; then
  gcloud container clusters create-auto "$GKE_MAIN_CLUSTER" \
    --project="$GKE_PROJECT" --region="$REGION" \
    --network="projects/${HOST_PROJECT}/global/networks/${NETWORK}" \
    --subnetwork="projects/${HOST_PROJECT}/regions/${REGION}/subnetworks/${GKE_MAIN_SUBNET}" \
    --cluster-secondary-range-name="$GKE_MAIN_POD_RANGE" \
    --enable-private-nodes --enable-private-endpoint \
    --master-ipv4-cidr="$GKE_MAIN_CP_CIDR" \
    --workload-pool="${GKE_PROJECT}.svc.id.goog"
fi

# CI/CD test Autopilot cluster
if ! gcloud container clusters describe "$GKE_TEST_CLUSTER" --region="$REGION" --project="$CICD_PROJECT" >/dev/null 2>&1; then
  gcloud container clusters create-auto "$GKE_TEST_CLUSTER" \
    --project="$CICD_PROJECT" --region="$REGION" \
    --network="projects/${HOST_PROJECT}/global/networks/${NETWORK}" \
    --subnetwork="projects/${HOST_PROJECT}/regions/${REGION}/subnetworks/${GKE_TEST_SUBNET}" \
    --cluster-secondary-range-name="$GKE_TEST_POD_RANGE" \
    --enable-private-nodes --master-ipv4-cidr="$GKE_TEST_CP_CIDR" \
    --workload-pool="${CICD_PROJECT}.svc.id.goog"
fi

echo '[OK] foundation stage complete'
echo 'NOTE: Cloud Build private pool, Cloud Run service, Workflow and their service-account IAM are kept as separate scripts/config because ETC_09 contains workload-specific definitions.'
