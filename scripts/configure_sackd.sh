#!/bin/bash

# Referenced from 

set -euo pipefail

AWS_REGION=${AWS_REGION:-}
cluster_id=${1:-$CLUSTER_ID}
region=${2:-$AWS_REGION}

function help() {
  cat <<EOF

  Usage: $0 <CLUSTER_ID> <AWS_REGION>

  Arguments:
    - CLUSTER_ID:                   PCS Cluster ID (e.g. pcs_wgs83921a)
    - AWS_REGION:                   AWS region to use (e.g. us-east-1).  

  Environment Variables:
    CLUSTER_ID                    PCS Cluster ID
    AWS_REGION                    AWS Region
EOF
}

# Fail if region or cluster_id is not provided
if [ -z "$region" ] || [ -z "$cluster_id" ]; then
    echo "ERROR: Missing 'AWS_REGION' or 'CLUSTER_ID'"
    help
    exit 1
fi

# Get cluster details
slurm_ip=$(aws pcs get-cluster --region $region --cluster-identifier $cluster_id --query "cluster.endpoints[?type=='SLURMCTLD'].privateIpAddress | [0]" --output text)
slurm_port=$(aws pcs get-cluster --region $region --cluster-identifier $cluster_id --query "cluster.endpoints[?type=='SLURMCTLD'].port | [0]" --output text)
slurm_key_arn=$(aws pcs get-cluster --region $region --cluster-identifier $cluster_id --query "cluster.slurmConfiguration.authKey.secretArn" --output text)

# Output the slurm details
echo "Slurm IP: $slurm_ip"
echo "Slurm Port: $slurm_port"
echo "Slurm Key ARN: $slurm_key_arn"

mkdir -p /etc/slurm

echo "Getting slurm key"
aws secretsmanager get-secret-value \
    --region $region \
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

echo "Finished!"
