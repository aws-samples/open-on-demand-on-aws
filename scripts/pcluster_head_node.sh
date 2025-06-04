#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Install packages for domain
yum -y -q install jq
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v -s http://169.254.169.254/latest/meta-data/instance-id)

OOD_STACK_NAME=$1
OOD_STACK=$(aws cloudformation describe-stacks --stack-name $OOD_STACK_NAME --region $REGION )

CLUSTER_NAME=$(aws ec2 describe-instances --instance-id=$INSTANCE_ID --region $REGION --query 'Reservations[].Instances[].Tags[?Key==`parallelcluster:cluster-name`].Value' --output text)
S3_CONFIG_BUCKET=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ClusterConfigBucket") | .OutputValue')

echo "[-] Configuring head_node from OnNodeConfigured" > /var/log/onnodeconfigured.log

# Add spack-users group
groupadd spack-users -g 4000

## Remove slurm cluster name; will be repopulated when instance restarts
rm -f /var/spool/slurm.state/clustername
sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
service sshd restart

echo "[-] Creating $CLUSTER_NAME.yml for OOD" >> /var/log/onnodeconfigured.log
mkdir -p /etc/ood/config/clusters.d
cat << EOF > /etc/ood/config/clusters.d/$CLUSTER_NAME.yml
---
v2:
  metadata:
    title: "$CLUSTER_NAME"
    hidden: false
  login:
    host: "$(hostname -s)"
  job:
    adapter: "slurm"
    cluster: "$CLUSTER_NAME"
    bin: "/bin"
    bin_overrides:
      sbatch: "/etc/ood/config/bin_overrides.py"
EOF

echo "[-] Uploading $CLUSTER_NAME.yml to S3" >> /var/log/onnodeconfigured.log
# Copy the cluster config to S3
aws s3 cp /etc/ood/config/clusters.d/$CLUSTER_NAME.yml s3://$S3_CONFIG_BUCKET/clusters/$CLUSTER_NAME.yml
echo "[-] $CLUSTER_NAME.yml uploaded to $S3_CONFIG_BUCKET/clusters/$CLUSTER_NAME.yml" >> /var/log/onnodeconfigured.log

cat >> /etc/bashrc << 'EOF'
PATH=$PATH:/shared/software/bin
EOF

echo "[-] Creating slurm.conf for Open OnDemand" >> /var/log/onnodeconfigured.log
# Build slurm.conf for Open OnDemand
SlurmctldHost=$(hostname -s)
ClusterName=$CLUSTER_NAME
AccountingStorageHost=$(hostname -s)
AccountingStoragePort=6819

cat << EOF > /tmp/ood-slurm.conf
SlurmUser=slurm
SlurmctldHost=$SlurmctldHost
ClusterName=$ClusterName
AuthType=auth/munge
CredType=cred/munge

# Slurm Accounting
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=$AccountingStorageHost
AccountingStoragePort=$AccountingStoragePort
EOF

# Copy slurm.conf to s3
echo "[-] Uploading slurm.conf to S3" >> /var/log/onnodeconfigured.log
aws s3 cp /tmp/ood-slurm.conf s3://${S3_CONFIG_BUCKET}/slurm/slurm.conf
echo "[-] slurm.conf uploaded to $S3_CONFIG_BUCKET/slurm/slurm.conf" >> /var/log/onnodeconfigured.log
