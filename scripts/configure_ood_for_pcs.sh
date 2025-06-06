#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

display_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --ood-stack <stack-name>        Name of the ood stack (required)"
    echo "  --cluster-name <cluster-name>   Name of the cluster (required)"
    echo "  --cluster-id <cluster-id>       Name of the PCS cluster (required)"
    echo "  --region <region>               AWS region (optional)"
    echo "  --help                          Display this help message"
    echo
    echo "Example:"
    echo "  $0 --ood-stack ood --cluster-name workshop-cluster --cluster-id pcs_8903213 --region us-east-1"
}

REGION=${AWS_REGION:-}

# Parse named parameters
while [[ $# -gt 0 ]]; do
    case $1 in
        --ood-stack)
            OOD_STACK="$2"
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
# Validate required parameters
required_params=("OOD_STACK" "CLUSTER_NAME" "CLUSTER_ID")
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

ClusterConfigBucket=$(aws cloudformation describe-stacks --stack-name $OOD_STACK --query "Stacks[0].Outputs[?OutputKey=='ClusterConfigBucket'].OutputValue" --output text)

slurm_ip=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.endpoints[?type=='SLURMCTLD'].privateIpAddress | [0]" --output text)
slurm_port=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.endpoints[?type=='SLURMCTLD'].port | [0]" --output text)
slurmdbd_ip=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.endpoints[?type=='SLURMDBD'].privateIpAddress | [0]" --output text)
slurmdbd_port=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.endpoints[?type=='SLURMDBD'].port | [0]" --output text)
AUTH="slurm"

echo "[-] Creating 'slurm.conf' file"
echo "[-] Cluster ID: $CLUSTER_ID"
echo "[-] Slurm IP: $slurm_ip"
echo "[-] Slurm Port: $slurm_port"
echo "[-] Slurmdbd IP: $slurmdbd_ip"
echo "[-] Slurmdbd Port: $slurmdbd_port"
echo "[-] Auth: $AUTH"
echo "[-] Cluster Config Bucket: $ClusterConfigBucket"

cat << EOF > /etc/slurm/slurm.conf
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
aws s3 cp /etc/slurm/slurm.conf s3://${ClusterConfigBucket}/slurm/

# Fix set_host value in bc_desktop 
rm -rf /var/www/ood/apps/sys/bc_desktop/submit.yml.erb
cat << EOF >> /var/www/ood/apps/sys/bc_desktop/submit.yml.erb
batch_connect:
template: vnc
websockify_cmd: "/usr/local/bin/websockify"
set_host: "host=\$(hostname | awk '{print \$1}')"
EOF

# Restart httpd
systemctl restart httpd

#########################################################
# Configure sackd
#########################################################
echo "[-] Configuring sackd"
# Get cluster details
slurm_key_arn=$(aws pcs get-cluster --region $REGION --cluster-identifier $CLUSTER_ID --query "cluster.slurmConfiguration.authKey.secretArn" --output text)

# Output the slurm details
echo "Slurm IP: $slurm_ip"
echo "Slurm Port: $slurm_port"
echo "Slurm Key ARN: $slurm_key_arn"

mkdir -p /etc/slurm

echo "Getting slurm key"
aws secretsmanager get-secret-value \
    --region $REGION \
    --secret-id $slurm_key_arn \
    --version-stage AWSCURRENT \
    --query 'SecretString' \
    --output text | base64 -d > /etc/slurm/slurm.key

# run this after slurm is installed so "slurm" user exists. 
chmod 0600 /etc/slurm/slurm.key
chown slurm:slurm /etc/slurm/slurm.key

echo "Configuring sackd service"
echo "SACKD_OPTIONS='--conf-server=${slurm_ip}:${slurm_port}'" > /etc/sysconfig/sackd

cat << EOF | sudo tee /etc/systemd/system/sackd.service
    [Unit]
    Description=Slurm auth and cred kiosk daemon
    After=network-online.target remote-fs.target
    Wants=network-online.target
    ConditionPathExists=/etc/sysconfig/sackd

    [Service]
    Type=notify
    EnvironmentFile=/etc/sysconfig/sackd
    User=slurm
    Group=slurm
    RuntimeDirectory=slurm
    RuntimeDirectoryMode=0755
    ExecStart=/usr/sbin/sackd --systemd \$SACKD_OPTIONS
    ExecReload=/bin/kill -HUP \$MAINPID
    KillMode=process
    LimitNOFILE=131072
    LimitMEMLOCK=infinity
    LimitSTACK=infinity

    [Install]
    WantedBy=multi-user.target
EOF

    sudo chown root:root /etc/systemd/system/sackd.service &&
        sudo chmod 0644 /etc/systemd/system/sackd.service

    echo "enabling sackd service"
    sudo systemctl daemon-reload && sudo systemctl enable sackd
    echo "starting sackd service"
    sudo systemctl start sackd    

echo "[-] Finished!"
