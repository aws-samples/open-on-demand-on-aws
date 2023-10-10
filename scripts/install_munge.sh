#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
DEBIAN_FRONTEND=noninteractive apt install munge libmunge-dev libmunge2 libssh2-1-dev man2html sshpass -y -q

# Try to copy down the file

echo "Copying munge key from ${CLUSTER_CONFIG_BUCKET} if found" >> /var/log/install.txt
# Try to copy down the file if it exists
aws s3api head-object --bucket $CLUSTER_CONFIG_BUCKET --key munge.key || NOT_EXIST=true
if [ ! $NOT_EXIST ]; then
  aws s3 cp s3://$CLUSTER_CONFIG_BUCKET/munge.key /etc/munge/munge.key
fi

# If the file doesn't exist, then we need to create it
if [[ ! -e /etc/munge/munge.key ]]; then
    echo "munge key does not exist, creating..." >> /var/log/install.txt
    dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key # From here: https://docs.01.org/clearlinux/latest/tutorials/hpc.html
else
    echo "munge key already exists, skipping..." >> /var/log/install.txt
fi

# Copy to S3 so we can put on other instances
if [ $NOT_EXIST ]; then
    aws s3 cp /etc/munge/munge.key s3://$CLUSTER_CONFIG_BUCKET/munge.key
fi

chown munge: /etc/munge/munge.key
chmod 400 /etc/munge/munge.key

systemctl start munge
systemctl enable munge