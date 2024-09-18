#!/bin/bash
set -eo pipefail
ARTIFACT_BUCKET=ood-assets-$(aws sts get-caller-identity --query Account --output text)
# Create an S3 bucket and upload the code there
aws s3 mb s3://$ARTIFACT_BUCKET --region us-east-1 &>/dev/null || true
aws s3 sync --delete --exclude "*" --include "assets/*" . s3://$ARTIFACT_BUCKET 

echo "[-] Assets deployed to s3 bucket '$ARTIFACT_BUCKET'"
