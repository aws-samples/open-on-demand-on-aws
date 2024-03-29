#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Installs amazon-efs-utils (https://github.com/aws/efs-utils)

# Install EFS
pushd /tmp && git clone https://github.com/aws/efs-utils
pushd efs-utils
./build-deb.sh
apt install ./build/amazon-efs-utils*deb -yq
popd

# # Mount EFS file system
mkdir /shared
# Add entry for fstab so mounts on restart
echo "$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone).$EFS_ID.efs.$AWS_REGION.amazonaws.com:/ /shared efs _netdev,noresvport,tls,iam 0 0" >> /etc/fstab
mount -a
mkdir -p /shared/home