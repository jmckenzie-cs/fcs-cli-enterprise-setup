#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"

export FALCON_CLIENT_ID=$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id crowdstrike/fcs-cli \
  --query SecretString --output text | jq -r '.client_id')

export FALCON_CLIENT_SECRET=$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id crowdstrike/fcs-cli \
  --query SecretString --output text | jq -r '.client_secret')
