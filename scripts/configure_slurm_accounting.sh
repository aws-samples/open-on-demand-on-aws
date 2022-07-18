# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
yum install slurm-slurmdbd -y -q

export RDS_SECRET=$(aws secretsmanager --region $AWS_REGION get-secret-value --secret-id $RDS_SECRET_ID --query SecretString --output text)
export RDS_USER=$(echo $RDS_SECRET | jq -r ".username")
export RDS_PASSWORD=$(echo $RDS_SECRET | jq -r ".password")
export RDS_ENDPOINT=$(echo $RDS_SECRET | jq -r ".host")
export RDS_PORT=$(echo $RDS_SECRET | jq -r ".port")

cat << EOF > /etc/slurm/slurmdbd.conf
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
LogFile=/var/log/slurm/slurmdbd.log
PidFile=/var/run/slurmdbd.pid
StorageType=accounting_storage/mysql
StorageUser=$RDS_USER
StoragePass=$RDS_PASSWORD
StorageHost=$RDS_ENDPOINT # Endpoint from RDS
StoragePort=$RDS_PORT  # Port from RDS
EOF

sed -i "s/AccountingStorageType=accounting_storage\/none/AccountingStorageType=accounting_storage\/slurmdbd/" /etc/slurm/slurm.conf

cat << EOF >> /etc/slurm/slurm.conf
# ACCOUNTING
AccountingStorageHost=$(hostname -s)
AccountingStorageUser=$RDS_USER
AccountingStoragePort=6819
EOF
# TODO: Accounting storage type is already on there; need to sed it

chmod 600 /etc/slurm/slurmdbd.conf
chown slurm /etc/slurm/slurmdbd.conf

# Start SLURM accounting
/sbin/slurmdbd

# TODO: First find out if the federation exists

systemctl restart slurmd
systemctl restart slurmctld

# If federation doesn't exist then create it
EXISTING_FEDERATION=$(sacctmgr list federation Name=ood-cluster -n)
if [ -z "$EXISTING_FEDERATION" ]; then
    sacctmgr add federation ood-cluster -i
fi
systemctl start slurmdbd
systemctl enable slurmdbd
# If this crashes restart; it crashes sometimes
sed -i '/\[Service]/a Restart=always\nRestartSec=5' /usr/lib/systemd/system/slurmdbd.service
systemctl daemon-reload