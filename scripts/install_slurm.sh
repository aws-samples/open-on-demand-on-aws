#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
dnf install make rpm-build readline-devel \
    pam-devel perl-Switch perl-ExtUtils\* mariadb105-devel \
    dbus-devel -y -q

cd /tmp
wget https://download.schedmd.com/slurm/slurm-"${SLURM_VERSION}".tar.bz2
tar -xvjf slurm-"${SLURM_VERSION}".tar.bz2
cd slurm-"${SLURM_VERSION}"
./configure --prefix=/usr --sysconfdir=/etc/slurm;
make -j$(nproc)
make contrib
make install
make install-contrib

mkdir /etc/slurm

cp etc/slurm.conf.example /etc/slurm/slurm.conf
cp etc/slurmdbd.conf.example /etc/slurm/slurmdbd.conf
cp etc/cgroup.conf.example /etc/slurm/cgroup.conf
cp etc/slurmd.service /etc/systemd/system
cp etc/slurmdbd.service /etc/systemd/system
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

sed -i "s/#SlurmdLogFile=/SlurmdLogFile=\/var\/log\/slurm\/slurmd.log/" /etc/slurm/slurm.conf
sed -i "s/#SlurmctldLogFile=/SlurmctldLogFile=\/var\/log\/slurm\/slurmctld.log/" /etc/slurm/slurm.conf

sed -i "s/SlurmctldHost=.*$/SlurmctldHost=$(hostname -s)/" /etc/slurm/slurm.conf
sed -i "s/NodeName=.*$/NodeName=$(hostname -s)/" /etc/slurm/slurm.conf

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
