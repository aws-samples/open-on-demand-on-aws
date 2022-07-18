# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
yum install munge munge-libs munge-devel libssh2-devel man2html sshpass -y -q

# Try to copy down the file
aws s3 cp s3://$CLUSTER_CONFIG_BUCKET/munge.key /etc/munge/munge.key


# If the file doesn't exist, then we need to create it
if [[ ! -e /etc/munge/munge.key ]]; then
    dd if=/dev/urandom bs=1 count=1024 > /etc/munge/munge.key # From here: https://docs.01.org/clearlinux/latest/tutorials/hpc.html
    # Copy to S3 so we can put on other instances
    aws s3 cp /etc/munge/munge.key s3://$CLUSTER_CONFIG_BUCKET/munge.key
fi

chown munge: /etc/munge/munge.key
chmod 400 /etc/munge/munge.key

systemctl start munge
systemctl enable munge