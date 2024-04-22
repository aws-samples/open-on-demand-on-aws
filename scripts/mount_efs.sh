#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Installs amazon-efs-utils (https://github.com/aws/efs-utils)

dnf -yq install amazon-efs-utils

# # Mount EFS file system
mkdir /shared
# Add entry for fstab so mounts on restart
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
echo "$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone).$EFS_ID.efs.$AWS_REGION.amazonaws.com:/ /shared efs _netdev,noresvport,tls,iam 0 0" >> /etc/fstab
mount -a
mkdir -p /shared/home
