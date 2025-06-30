#!/bin/bash
set -eo pipefail

AWS_REGION=${AWS_REGION:-us-east-1}
ARTIFACT_BUCKET=ood-assets-$(aws sts get-caller-identity --query Account --output text)

# Create an S3 bucket and upload the code there
echo "[-] Deploying assets to AWS region '$AWS_REGION'"
if ! aws s3 mb s3://$ARTIFACT_BUCKET --region $AWS_REGION 2>&1; then
    echo "Error: Failed to create S3 bucket '$ARTIFACT_BUCKET'"
    exit 1
fi

# Upload the assets to the S3 bucket
echo "[-] Uploading assets to S3 bucket '$ARTIFACT_BUCKET'"
aws s3 sync --delete --exclude "*" --include "assets/*" . s3://$ARTIFACT_BUCKET 

# Print the URL of the assets
echo "[-] Finished!"
