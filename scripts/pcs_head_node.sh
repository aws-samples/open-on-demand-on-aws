#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

display_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --ood-stack <stack-name>     Name of the ood stack (required)"
    echo "  --cluster-id <cluster-id>   Name of the infrastructure stack (required)"
    echo "  --region <region>            AWS region (optional)"
    echo "  --help                       Display this help message"
    echo
    echo "Example:"
    echo "  $0 --ood-stack ood --cluster-id pcs_8903213 --region us-east-1"
}

REGION=${AWS_REGION:-}

# Parse named parameters
while [[ $# -gt 0 ]]; do
    case $1 in
        --ood-stack)
            OOD_STACK="$2"
            shift 2
            ;;
        --cluster-id)
            CLUSTER_ID="$2"
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
            log "ERROR" "Unknown parameter: $1"
            display_help
            exit 1
            ;;
    esac
done

ClusterConfigBucket=$(aws cloudformation describe-stacks --stack-name $OOD_STACK --query "Stacks[0].Outputs[?OutputKey=='ClusterConfigBucket'].OutputValue" --output text)

slurm_ip=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.endpoints[0].privateIpAddress")
slurm_port=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.endpoints[0].port")
slurmdbd_ip=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.endpoints[0].privateIpAddress")
slurmdbd_port=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.endpoints[0].port")
AUTH="slurm"

echo "[-] Creating 'slurm.conf' file"
echo "[-] Cluster ID: $CLUSTER_ID"
echo "[-] Slurm IP: $slurm_ip"
echo "[-] Slurm Port: $slurm_port"
echo "[-] Slurmdbd IP: $slurmdbd_ip"
echo "[-] Slurmdbd Port: $slurmdbd_port"
echo "[-] Auth: $AUTH"
echo "[-] Cluster Config Bucket: $ClusterConfigBucket"

cat << EOF > slurm.conf
SlurmctldHost=$slurm_ip
SlurmctldPort=$slurm_port
ClusterName="workshop-cluster"
AuthType=auth/$AUTH
CredType=cred/$AUTH

# Slurm Accounting
AccountingStorageHost=$slurmdbd_ip
AccountingStoragePort=$slurmdbd_port
EOF

echo "[-] Uploading 'slurm.conf' to '${ClusterConfigBucket}'"
aws s3 cp slurm.conf s3://${ClusterConfigBucket}/slurm/

echo "[-] Finished!"
