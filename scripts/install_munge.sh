#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
dnf install munge munge-libs munge-devel libssh2-devel sshpass -y -q

# Install munge 0.5.16
wget https://github.com/dun/munge/releases/download/munge-0.5.16/munge-0.5.16.tar.xz
dnf -y install zlib-devel openssl-devel bzip2-devel gcc
rpmbuild -tb munge-0.5.16.tar.xz
dnf -y install /rpmbuild/RPMS/x86_64/munge-0.5.16-1.el9.x86_64.rpm \
/rpmbuild/RPMS/x86_64/munge-devel-0.5.16-1.el9.x86_64.rpm \
/rpmbuild/RPMS/x86_64/munge-libs-0.5.16-1.el9.x86_64.rpm

# Try to copy down the file
# Add aws cli to path
export PATH=$PATH:/usr/local/bin

# Write munge key if a value exists in the secret value
MUNGEKEY_SECRET=$(aws secretsmanager get-secret-value \
    --secret-id "${MUNGEKEY_SECRET_ID}" \
    --query SecretString \
    --region "${AWS_REGION}" \
    --output text 2> /dev/null) 

if [[ -z $MUNGEKEY_SECRET ]]; then
    echo "munge key does not exist, creating..." >> /var/log/install.txt
    dd if=/dev/random bs=128 count=1 > /etc/munge/munge.key # From here: https://docs.01.org/clearlinux/latest/tutorials/hpc.html

    # base64 encode the munge key and add to secrets manager
    MUNGEKEY_SECRET_ENCODED=$(base64 -w0 /etc/munge/munge.key)

    aws secretsmanager put-secret-value \
    --secret-id "${MUNGEKEY_SECRET_ID}" \
    --secret-string "$MUNGEKEY_SECRET_ENCODED"
else
    echo "munge key already exists, skipping..." >> /var/log/install.txt

    # base64 decode the munge key and write to file
    echo -n $MUNGEKEY_SECRET | base64 -d > /etc/munge/munge.key
fi

chown munge: /etc/munge/munge.key
chmod 400 /etc/munge/munge.key

systemctl start munge
systemctl enable munge
