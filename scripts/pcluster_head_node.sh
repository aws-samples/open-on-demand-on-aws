# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#!/bin/bash

# Install packages for domain
yum -y -q install jq mysql amazon-efs-utils
REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

OOD_STACK_NAME=$1

OOD_STACK=$(aws cloudformation describe-stacks --stack-name $OOD_STACK_NAME --region $REGION )

STACK_NAME=$(aws ec2 describe-instances --instance-id=$INSTANCE_ID --region $REGION --query 'Reservations[].Instances[].Tags[?Key==`parallelcluster:cluster-name`].Value' --output text)
OOD_SECRET_ID=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="SecretId") | .OutputValue')
RDS_SECRET_ID=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="DBSecretId") | .OutputValue')
EFS_ID=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="EFSMountId") | .OutputValue')
S3_CONFIG_BUCKET=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ClusterConfigBucket") | .OutputValue')

export RDS_SECRET=$(aws secretsmanager --region $REGION get-secret-value --secret-id $RDS_SECRET_ID --query SecretString --output text)
export RDS_USER=$(echo $RDS_SECRET | jq -r ".username")
export RDS_PASSWORD=$(echo $RDS_SECRET | jq -r ".password")
export RDS_ENDPOINT=$(echo $RDS_SECRET | jq -r ".host")
export RDS_PORT=$(echo $RDS_SECRET | jq -r ".port")

# Add entry for fstab so mounts on restart
mkdir /shared
echo "$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone).${EFS_ID}.efs.$REGION.amazonaws.com:/ /shared efs _netdev,noresvport,tls,iam 0 0" >> /etc/fstab
mount -a

# Add spack-users group
groupadd spack-users -g 4000

/shared/copy_users.sh

## Remove slurm cluster name; will be repopulated when instance restarts
rm -f /var/spool/slurm.state/clustername
sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
service sshd restart

#This line allows the users to login without the domain name
sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' /etc/sssd/sssd.conf
sed -i 's/fallback_homedir = \/home\/%u/fallback_homedir = \/shared\/home\/%u/' -i /etc/sssd/sssd.conf
sleep 1
systemctl restart sssd


export SLURM_VERSION=$(. /etc/profile && sinfo --version | cut -d' ' -f 2)
sed -i "s/ClusterName=.*$/ClusterName=$STACK_NAME/" /opt/slurm/etc/slurm.conf

mkdir -p /etc/ood/config/clusters.d
cat << EOF > /etc/ood/config/clusters.d/$STACK_NAME.yml
---
v2:
  metadata:
    title: "$STACK_NAME"
    hidden: false
  login:
    host: "$(hostname -s)"
  job:
    adapter: "slurm"
    cluster: "$STACK_NAME"
    bin: "/bin"
    bin_overrides:
      sbatch: "/etc/ood/config/bin_overrides.py"
EOF

cat << EOF > /opt/slurm/etc/slurmdbd.conf
ArchiveEvents=yes
ArchiveJobs=yes
ArchiveResvs=yes
ArchiveSteps=no
ArchiveSuspend=no
ArchiveTXN=no
ArchiveUsage=no
AuthType=auth/munge
DbdHost=$(hostname -s)
DbdPort=6819
DebugLevel=info
PurgeEventAfter=1month
PurgeJobAfter=12month
PurgeResvAfter=1month
PurgeStepAfter=1month
PurgeSuspendAfter=1month
PurgeTXNAfter=12month
PurgeUsageAfter=24month
SlurmUser=slurm
LogFile=/var/log/slurmdbd.log
PidFile=/var/run/slurmdbd.pid
StorageType=accounting_storage/mysql
StorageUser=$RDS_USER
StoragePass=$RDS_PASSWORD
StorageHost=$RDS_ENDPOINT # Endpoint from RDS console
StoragePort=$RDS_PORT  # Port from RDS console
EOF

cat << EOF >> /opt/slurm/etc/slurm.conf
# ACCOUNTING
JobAcctGatherType=jobacct_gather/linux
JobAcctGatherFrequency=30
AccountingStorageType=accounting_storage/slurmdbd
AccountingStorageHost=$(hostname -s)
AccountingStorageUser=$RDS_USER
AccountingStoragePort=6819
EOF

chmod 600 /opt/slurm/etc/slurmdbd.conf
chown slurm /opt/slurm/etc/slurmdbd.conf

# Copy Common Munge Key
aws s3 cp s3://$S3_CONFIG_BUCKET/munge.key /etc/munge/munge.key
chown munge: /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
systemctl restart munge

# Add cluster to slurm accounting
sacctmgr add cluster $STACK_NAME
systemctl restart slurmctld
systemctl restart slurmdbd
systemctl restart slurmctld # TODO: Investigate why this fixes clusters not registered issues

aws s3 cp /etc/ood/config/clusters.d/$STACK_NAME.yml s3://$S3_CONFIG_BUCKET/clusters/$STACK_NAME.yml
