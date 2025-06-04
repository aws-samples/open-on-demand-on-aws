#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

display_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --ood-stack <stack-name>        Name of the ood stack (required)"
    echo "  --cluster-type <type>           Type of cluster (pcs, pcluster) (required)"
    echo "  --cluster-name <cluster-name>   Name of the cluster (required)"
    echo "  --cluster-id <cluster-id>       Name of the PCS cluster (required if cluster-type=pcs)"
    echo "  --pcluster-stack <stack-name>   Name of the pcluster stack (required if cluster-type=pcluster)"
    echo "  --region <region>               AWS region (optional)"
    echo "  --help                          Display this help message"
    echo
    echo "Example:"
    echo "  $0 --ood-stack ood --cluster-type pcs --cluster-name workshop-cluster --cluster-id pcs_8903213 --region us-east-1"
    echo "  $0 --ood-stack ood --cluster-type pcluster --cluster-name workshop-cluster --pcluster-stack workshop-pcluster --region us-east-1"
}

REGION=${AWS_REGION:-}

# Parse named parameters
while [[ $# -gt 0 ]]; do
    case $1 in
        --ood-stack)
            OOD_STACK="$2"
            shift 2
            ;;
        --cluster-type)
            CLUSTER_TYPE="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --cluster-id)
            CLUSTER_ID="$2"
            shift 2
            ;;
        --pcluster-stack)
            PCLUSTER_STACK="$2"
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

echo "[-] Validating parameters"
if [ -z "$OOD_STACK" ] || [ -z "$CLUSTER_TYPE" ] || [ -z "$CLUSTER_NAME" ]; then
    echo "[!] OOD stack, cluster type, and cluster name are required"
    display_help
    exit 1
fi

ClusterConfigBucket=$(aws cloudformation describe-stacks --stack-name $OOD_STACK --query "Stacks[0].Outputs[?OutputKey=='ClusterConfigBucket'].OutputValue" --output text)
PCLUSTER_SLURMCTLD_PORT=6817
PCLUSTER_SLURMDBD_PORT=6819

if [ "$CLUSTER_TYPE" == "pcs" ]; then
    if [ -z "$CLUSTER_ID" ]; then
        echo "[!] --cluster-id is required for pcs"
        exit 1
    fi
    slurm_ip=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.endpoints[?type=='SLURMCTLD'].privateIpAddress | [0]" --output text)
    slurm_port=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.endpoints[?type=='SLURMCTLD'].port | [0]" --output text)
    slurmdbd_ip=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.endpoints[?type=='SLURMDBD'].privateIpAddress | [0]" --output text)
    slurmdbd_port=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.endpoints[?type=='SLURMDBD'].port | [0]" --output text)
    AUTH="slurm"

elif [ "$CLUSTER_TYPE" == "pcluster" ]; then
    if [ -z "$PCLUSTER_STACK" ]; then
        echo "[!] --pcluster-stack is required for pcluster"
        exit 1
    fi
    headnode_private_ip=$(aws cloudformation describe-stacks --stack-name $PCLUSTER_STACK --query "Stacks[0].Outputs[?OutputKey=='HeadNodePrivateIP'].OutputValue" --output text)
    slurm_ip=$headnode_private_ip
    slurm_port=$PCLUSTER_SLURMCTLD_PORT
    slurmdbd_ip=$headnode_private_ip
    slurmdbd_port=$PCLUSTER_SLURMDBD_PORT
    AUTH="munge"
else
    log "ERROR" "Invalid cluster type: $CLUSTER_TYPE"
    exit 1
fi

echo "[-] Creating 'slurm.conf' file"
echo "[-] Cluster ID: $CLUSTER_ID"
echo "[-] Slurm IP: $slurm_ip"
echo "[-] Slurm Port: $slurm_port"
echo "[-] Slurmdbd IP: $slurmdbd_ip"
echo "[-] Slurmdbd Port: $slurmdbd_port"
echo "[-] Auth: $AUTH"
echo "[-] Cluster Config Bucket: $ClusterConfigBucket"

cat << EOF > slurm.conf
SlurmUser=slurm
SlurmctldHost=$slurm_ip
SlurmctldPort=$slurm_port
ClusterName=$CLUSTER_NAME
AuthType=auth/$AUTH
CredType=cred/$AUTH

# Slurm Accounting
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=$slurmdbd_ip
AccountingStoragePort=$slurmdbd_port
EOF

echo "[-] Uploading 'slurm.conf' to '${ClusterConfigBucket}'"
aws s3 cp slurm.conf s3://${ClusterConfigBucket}/slurm/


# Fix set_host value in bc_desktop 
if [ "$CLUSTER_TYPE" == "pcs" ]; then
    rm -rf /var/www/ood/apps/sys/bc_desktop/submit.yml.erb
    cat << EOF >> /var/www/ood/apps/sys/bc_desktop/submit.yml.erb
    batch_connect:
    template: vnc
    websockify_cmd: "/usr/local/bin/websockify"
    set_host: "host=\$(hostname | awk '{print \$1}')
EOF
fi

echo "[-] Finished!"
