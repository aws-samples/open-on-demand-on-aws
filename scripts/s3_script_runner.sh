#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -euo pipefail

display_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --instance-id <instance-id>      ID of the OOD instance (required)"
    echo "  --document-name <doc-name>       Name of the SSM document (required)"
    echo "  --bucket-name <bucket-name>      Name of the cluster config bucket (required)"
    echo "  --script-key <script-key>        Key of the script in S3 bucket (optional, defaults to configure_ood_for_pcs.sh)"
    echo "  --script-args <script-args>      Arguments to pass to the script (required - e.g. pcs_shcwlzxgr9 us-east-1)"
    echo "  --region <region>                AWS region (optional)"
    echo "  --help                           Display this help message"
    echo
    echo "Example:"
    echo "  $0 --instance-id i-1234567890abcdef0 --bucket-name my-bucket --document-name my-doc --script-key my-script.sh --script-args "list of args" --region us-east-1"
}

REGION=${AWS_REGION:-}
SCRIPT_KEY="configure_ood_for_pcs.sh"

# Parse named parameters
while [[ $# -gt 0 ]]; do
    case $1 in
        --instance-id)
            OOD_INSTANCE_ID="$2"
            shift 2
            ;;
        --bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        --document-name)
            DOCUMENT_NAME="$2"
            shift 2
            ;;
        --script-key)
            SCRIPT_KEY="$2"
            shift 2
            ;;
        --script-args)
            SCRIPT_ARGS="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --help)
            display_help
            exit 0
            ;;
        *)
            echo "ERROR: Unknown parameter: $1"
            display_help
            exit 1
            ;;
    esac
done

required_params=("OOD_INSTANCE_ID" "DOCUMENT_NAME" "BUCKET_NAME" "SCRIPT_KEY" "SCRIPT_ARGS")
missing_params=()

for param in "${required_params[@]}"; do
    if [ -z "${!param}" ]; then
        missing_params+=("$param")
    fi
done

if [ ${#missing_params[@]} -gt 0 ]; then
    echo "[!] The following required parameters are missing: ${missing_params[*]}"
    display_help
    exit 1
fi

aws ssm send-command \
    --instance-ids "$OOD_INSTANCE_ID" \
    --document-name "$DOCUMENT_NAME" \
    --parameters "$(jq -n \
        --arg bucket "$BUCKET_NAME" \
        --arg script "$SCRIPT_KEY" \
        --arg args "$SCRIPT_ARGS" \
        '{
            bucketName: [$bucket],
            scriptKey: [$script],
            scriptArgs: [$args]
        }')" \
    --comment "Running $SCRIPT_KEY with dynamic args." \
    --output text \
    --query "Command.CommandId"
