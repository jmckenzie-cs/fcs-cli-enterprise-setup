#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
export FALCON_API_URL="${FALCON_API_URL:-https://api.crowdstrike.com}"

export FALCON_CLIENT_ID=$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id crowdstrike/fcs-cli \
  --query SecretString --output text | jq -r '.client_id')

export FALCON_CLIENT_SECRET=$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id crowdstrike/fcs-cli \
  --query SecretString --output text | jq -r '.client_secret')

# FCS CLI runtime credentials
export FALCON_FCS_CLIENT_ID="$FALCON_CLIENT_ID"
export FALCON_FCS_CLIENT_SECRET="$FALCON_CLIENT_SECRET"
export FALCON_FCS_FALCON_REGION="${FALCON_FCS_FALCON_REGION:-us-1}"
