#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

################################
# Install Slurm
################################

echo "[-] Installing prerequisites for slurm"
dnf install make rpm-build readline-devel \
    pam-devel perl-Switch perl-ExtUtils\* mariadb105-devel \
    dbus-devel -y -q

cd /tmp
wget https://download.schedmd.com/slurm/slurm-"${SLURM_VERSION}".tar.bz2
tar -xvjf slurm-"${SLURM_VERSION}".tar.bz2
cd slurm-"${SLURM_VERSION}"
echo "[-] configuring slurm"
./configure --prefix=/usr --sysconfdir=/etc/slurm;
make -j$(nproc)
make contrib
make install
make install-contrib

echo "[-] finishing installing slurm"
mkdir /etc/slurm

cp etc/cgroup.conf.example /etc/slurm/cgroup.conf
cp etc/slurmd.service /etc/systemd/system
cp etc/slurmctld.service /etc/systemd/system

chown slurm -R /etc/slurm

# Create slurm user
useradd slurm

mkdir /var/spool/slurmctld
chown slurm: /var/spool/slurmctld

mkdir /var/spool/slurmd
chown slurm: /var/spool/slurmd
chmod 755 /var/spool/slurmd

mkdir /var/spool/slurm
mkdir -p /var/log/slurm
chown slurm: /var/spool/slurm
chown slurm: /var/log/slurm

# Copy any existing slurm configurations
aws s3 sync s3://${CLUSTER_CONFIG_BUCKET}/slurm /etc/slurm/ --exact-timestamps

# Check if slurm.conf exists. 
# If not create the default configuration
if [ ! -f /etc/slurm/slurm.conf ]; then
    echo "[-] slurm.conf not found, copying example"
    cp etc/slurm.conf.example /etc/slurm/slurm.conf

    sed -i "s/#SlurmdLogFile=/SlurmdLogFile=\/var\/log\/slurm\/slurmd.log/" /etc/slurm/slurm.conf
    sed -i "s/#SlurmctldLogFile=/SlurmctldLogFile=\/var\/log\/slurm\/slurmctld.log/" /etc/slurm/slurm.conf

    sed -i "s/SlurmctldHost=.*$/SlurmctldHost=$(hostname -s)/" /etc/slurm/slurm.conf
    sed -i "s/NodeName=.*$/NodeName=$(hostname -s)/" /etc/slurm/slurm.conf
fi

# Add hostname -s to /etc/hosts
echo "127.0.0.1 $(hostname -s)" >> /etc/hosts

systemctl start slurmctld
systemctl start slurmd
systemctl enable slurmd
systemctl enable slurmctld

# If these crash restart; it crashes sometimes
sed -i '/\[Service]/a Restart=always\nRestartSec=5' /etc/systemd/system/slurmctld.service
sed -i '/\[Service]/a Restart=always\nRestartSec=5' /etc/systemd/system/slurmd.service
systemctl daemon-reload

################################
# Configure Slurm Accounting
################################

export RDS_SECRET=$(aws secretsmanager --region $AWS_REGION get-secret-value --secret-id $RDS_SECRET_ID --query SecretString --output text)
export RDS_USER=$(echo $RDS_SECRET | jq -r ".username")
export RDS_PASSWORD=$(echo $RDS_SECRET | jq -r ".password")
export RDS_ENDPOINT=$(echo $RDS_SECRET | jq -r ".host")
export RDS_PORT=$(echo $RDS_SECRET | jq -r ".port")
export RDS_DBNAME=$(echo $RDS_SECRET | jq -r ".dbname")

# Check if slurmdbd.conf already exists.
# If not, create the default configuration
if [ ! -f /etc/slurm/slurmdbd.conf ]; then
    echo "[-] slurmdbd.conf not found, copying example"

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
    StorageLoc=$RDS_DBNAME # DBName from RDS
EOF
    # Change AccountingStorageType from 'none' to 'slurmdbd'
    sed -i "s/AccountingStorageType=accounting_storage\/none/AccountingStorageType=accounting_storage\/slurmdbd/" /etc/slurm/slurm.conf

    cat << EOF >> /etc/slurm/slurm.conf
    # ACCOUNTING
    AccountingStorageHost=$(hostname -s)
    AccountingStorageUser=$RDS_USER
    AccountingStoragePort=6819
EOF
fi

cp etc/slurmdbd.service /etc/systemd/system

chmod 600 /etc/slurm/slurmdbd.conf
chown slurm /etc/slurm/slurmdbd.conf

# Start SLURM accounting
# /usr/local/sbin/slurmdbd
/usr/sbin/slurmctld

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
sed -i '/\[Service]/a Restart=always\nRestartSec=5' /etc/systemd/system/slurmdbd.service
systemctl daemon-reload

# Copy slurm.conf to s3
aws s3 cp /etc/slurm/slurm.conf s3://${CLUSTER_CONFIG_BUCKET}/slurm/
# Copy slurmdbd.conf to s3
aws s3 cp /etc/slurm/slurmdbd.conf s3://${CLUSTER_CONFIG_BUCKET}/slurm/
