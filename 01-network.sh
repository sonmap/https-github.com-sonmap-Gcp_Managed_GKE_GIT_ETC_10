#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/config.env"

exists_subnet(){ gcloud compute networks subnets describe "$1" --region="$REGION" --project="$HOST_PROJECT" >/dev/null 2>&1; }

create_subnet(){
  local name="$1" cidr="$2" secondary="${3:-}"
  if exists_subnet "$name"; then echo "[SKIP] subnet $name"; return; fi
  args=(gcloud compute networks subnets create "$name" --project="$HOST_PROJECT" --region="$REGION" --network="$NETWORK" --range="$cidr" --enable-private-ip-google-access)
  [[ -n "$secondary" ]] && args+=(--secondary-range="$secondary")
  "${args[@]}"
}

create_subnet "$ILB_SUBNET" "$ILB_SUBNET_CIDR"
if ! gcloud compute addresses describe "$ILB_IP_NAME" --region="$REGION" --project="$HOST_PROJECT" >/dev/null 2>&1; then
  gcloud compute addresses create "$ILB_IP_NAME" --project="$HOST_PROJECT" --region="$REGION" --subnet="$ILB_SUBNET" --addresses="$ILB_IP"
fi

if ! exists_subnet "$PROXY_SUBNET"; then
  gcloud compute networks subnets create "$PROXY_SUBNET" --project="$HOST_PROJECT" --region="$REGION" --network="$NETWORK" --range="$PROXY_SUBNET_CIDR" --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE
fi

create_subnet "$GKE_MAIN_SUBNET" "$GKE_MAIN_SUBNET_CIDR" "${GKE_MAIN_POD_RANGE}=${GKE_MAIN_POD_CIDR}"
create_subnet "$GKE_TEST_SUBNET" "$GKE_TEST_SUBNET_CIDR" "${GKE_TEST_POD_RANGE}=${GKE_TEST_POD_CIDR}"
create_subnet "$CLOUDRUN_SUBNET" "$CLOUDRUN_SUBNET_CIDR"
create_subnet "$TASK_SUBNET" "$TASK_SUBNET_CIDR"

if ! gcloud compute addresses describe "$CB_PSA_NAME" --global --project="$HOST_PROJECT" >/dev/null 2>&1; then
  addr="${CB_PSA_CIDR%/*}"; prefix="${CB_PSA_CIDR#*/}"
  gcloud compute addresses create "$CB_PSA_NAME" --project="$HOST_PROJECT" --global --purpose=VPC_PEERING --addresses="$addr" --prefix-length="$prefix" --network="$NETWORK"
fi

gcloud services enable servicenetworking.googleapis.com --project="$HOST_PROJECT"
if ! gcloud services vpc-peerings list --network="$NETWORK" --project="$HOST_PROJECT" --format='value(service)' | grep -qx 'servicenetworking.googleapis.com'; then
  gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com --ranges="$CB_PSA_NAME" --network="$NETWORK" --project="$HOST_PROJECT"
fi

echo "[OK] network stage complete"
