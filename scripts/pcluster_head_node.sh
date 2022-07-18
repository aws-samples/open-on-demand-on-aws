# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#!/bin/bash

# Install packages for domain
yum -y -q install sssd realmd krb5-workstation samba-common-tools jq mysql amazon-efs-utils
REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

OOD_STACK_NAME=$1

OOD_STACK=$(aws cloudformation describe-stacks --stack-name $OOD_STACK_NAME --region $REGION )

STACK_NAME=$(aws ec2 describe-instances --instance-id=$INSTANCE_ID --region $REGION --query 'Reservations[].Instances[].Tags[?Key==`parallelcluster:cluster-name`].Value' --output text)
OOD_SECRET_ID=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="SecretId") | .OutputValue')
AD_PASSWORD_SECRET=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ADAdministratorSecretARN") | .OutputValue')
RDS_SECRET_ID=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="DBSecretId") | .OutputValue')
EFS_ID=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="EFSMountId") | .OutputValue')

export AD_SECRET=$(aws secretsmanager --region $REGION get-secret-value --secret-id $OOD_SECRET_ID --query SecretString --output text)
export S3_CONFIG_BUCKET=$(echo $AD_SECRET | jq -r ".ClusterConfigBucket")
export DOMAIN_NAME=$(echo $AD_SECRET | jq -r ".DomainName")
export TOP_LEVEL_DOMAIN=$(echo $AD_SECRET | jq -r ".TopLevelDomain")

export RDS_SECRET=$(aws secretsmanager --region $REGION get-secret-value --secret-id $RDS_SECRET_ID --query SecretString --output text)
export RDS_USER=$(echo $RDS_SECRET | jq -r ".username")
export RDS_PASSWORD=$(echo $RDS_SECRET | jq -r ".password")
export RDS_ENDPOINT=$(echo $RDS_SECRET | jq -r ".host")
export RDS_PORT=$(echo $RDS_SECRET | jq -r ".port")

export AD_PASSWORD=$(aws secretsmanager --region $REGION get-secret-value --secret-id $AD_PASSWORD_SECRET --query SecretString --output text)

# Join head node to the domain; PCluster doesn't do this by default
echo $AD_PASSWORD | realm join -v -U Administrator $DOMAIN_NAME.$TOP_LEVEL_DOMAIN --install=/

# Add entry for fstab so mounts on restart
mkdir /shared
echo "$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone).${EFS_ID}.efs.$REGION.amazonaws.com:/ /shared efs _netdev,noresvport,tls,iam 0 0" >> /etc/fstab
mount -a

/shared/copy_users.sh

#This line allows the users to login without the domain name
sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' /etc/sssd/sssd.conf
#This line configure sssd to create the home directories in the shared folder
sed -i 's/fallback_homedir = \/home\/%u/fallback_homedir = \/shared\/%u/' -i /etc/sssd/sssd.conf
# sed -i '/fallback_homedir/c\fallback_homedir = /home/%u' /etc/sssd/sssd.conf
sleep 1
systemctl restart sssd
# This line is required for AWS Parallel Cluster to understand correctly the custom domain
sed -i "s/--fail \${local_hostname_url}/--fail \${local_hostname_url} | awk '{print \$1}'/g" /opt/parallelcluster/scripts/compute_ready


## Remove slurm cluster name; will be repopulated when instance restarts
rm -f /var/spool/slurm.state/clustername
sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
service sshd restart

# Provided in Pcluster v2, not sure if it is in v3
# defines "stack_name" for the cluster (cfn stack name)
source "/etc/parallelcluster/cfnconfig"

export SLURM_VERSION=$(. /etc/profile && sinfo --version | cut -d' ' -f 2)
# Override SLURM to use long cluster name (based on pcluster scheme).
# This allows later clusters with same name to "restore" accounting
# ${stack_name} comes from /etc/paralelcluster/cfnconfig
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

cat <<EOF >> /etc/systemd/system/slurmdbd.service
[Unit]
Description=Slurm DBD accounting daemon
After=network.target munge.service
ConditionPathExists=/opt/slurm/etc/slurmdbd.conf

[Service]
Type=simple
Restart=always
StartLimitIntervalSec=0
RestartSec=5
ExecStart=/opt/slurm/sbin/slurmdbd -D $SLURMDBD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
LimitNOFILE=65536
TasksMax=infinity
ExecStartPost=/bin/systemctl restart slurmctld

[Install]
WantedBy=multi-user.target

EOF

# Start SLURM accounting
systemctl enable slurmdbd
systemctl start slurmdbd

# Join federation
sacctmgr modify cluster $STACK_NAME set federation=ood-cluster -i
systemctl restart slurmctld
systemctl restart slurmdbd

aws s3 cp /etc/ood/config/clusters.d/$STACK_NAME.yml s3://$S3_CONFIG_BUCKET/clusters/$STACK_NAME.yml

systemctl restart sssd