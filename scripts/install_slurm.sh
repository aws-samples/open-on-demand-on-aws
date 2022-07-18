# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
touch /var/log/install.txt

yum install slurm slurm-devel slurm-slurmd slurm-slurmctld -y -q >> /var/log/install.txt

mkdir /var/spool/slurmd
chown slurm: /var/spool/slurmd
chmod 755 /var/spool/slurmd
mkdir -p /var/log/slurm

# touch /var/log/slurmd.log
# chown slurm: /var/log/slurmd.log
chown slurm: /var/spool/slurm
chown slurm: /var/log/slurm

sed -i "s/#SlurmdLogFile=/SlurmdLogFile=\/var\/log\/slurm\/slurmd.log/" /etc/slurm/slurm.conf
sed -i "s/#SlurmctldLogFile=/SlurmctldLogFile=\/var\/log\/slurm\/slurmctld.log/" /etc/slurm/slurm.conf

# Add hostname -s to /etc/hosts
echo "127.0.0.1 $(hostname -s)" >> /etc/hosts

# TODO: Do we need both?
systemctl start slurmctld
systemctl start slurmd
systemctl enable slurmd
systemctl enable slurmctld

# If these crash restart; it crashes sometimes
sed -i '/\[Service]/a Restart=always\nRestartSec=5' /usr/lib/systemd/system/slurmctld.service
sed -i '/\[Service]/a Restart=always\nRestartSec=5' /usr/lib/systemd/system/slurmd.service
systemctl daemon-reload