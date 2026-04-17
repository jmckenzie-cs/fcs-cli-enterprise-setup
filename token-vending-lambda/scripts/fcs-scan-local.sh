#!/usr/bin/env bash
# scripts/fcs-scan-local.sh
#
# Local developer wrapper — fetches a short-lived FCS token from the
# Deere token vending Lambda and runs an FCS CLI image scan.
#
# Prerequisites:
#   - AWS CLI configured with SSO or a role that has lambda:InvokeFunction
#     on crowdstrike-fcs-token-vend
#   - fcs CLI installed and on $PATH
#   - jq installed
#
# Usage:
#   ./scripts/fcs-scan-local.sh <image>:<tag> [additional fcs flags...]
#
# Examples:
#   ./scripts/fcs-scan-local.sh myapp:latest
#   ./scripts/fcs-scan-local.sh myapp:latest --upload
#   ./scripts/fcs-scan-local.sh myapp:latest --minimum-severity high --upload

set -euo pipefail

IMAGE="${1:?Error: image name required. Usage: fcs-scan-local.sh <image>:<tag> [flags...]}"
shift

AWS_REGION="${AWS_REGION:-us-east-1}"
FALCON_REGION="${FALCON_REGION:-us-1}"
LAMBDA_FUNCTION="${LAMBDA_FUNCTION:-crowdstrike-fcs-token-vend}"

echo "Requesting FCS token..."
RESPONSE=$(aws lambda invoke \
  --region "$AWS_REGION" \
  --function-name "$LAMBDA_FUNCTION" \
  --payload '{}' \
  --output text \
  --query Payload \
  /dev/stdout)

TOKEN=$(echo "$RESPONSE" | jq -r '.body | fromjson | .token')
EXPIRES_IN=$(echo "$RESPONSE" | jq -r '.body | fromjson | .expires_in')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "Error: failed to retrieve token from Lambda" >&2
  exit 1
fi

echo "Token acquired (expires in ${EXPIRES_IN}s). Starting scan..."

fcs scan image "$IMAGE" \
  --falcon-token "$TOKEN" \
  --falcon-region "$FALCON_REGION" \
  "$@"
