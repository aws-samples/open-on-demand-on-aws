#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

yum -y -q install jq amazon-efs-utils

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
# Get OOD Stack data
OOD_STACK_NAME=$1
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/placement/region)

OOD_STACK=$(aws cloudformation describe-stacks --stack-name $OOD_STACK_NAME --region $REGION )


S3_CONFIG_BUCKET=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ClusterConfigBucket") | .OutputValue')
EFS_ID=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="EFSMountId") | .OutputValue')

# Add entry for fstab so mounts on restart
mkdir /shared
echo "$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v -s http://169.254.169.254/latest/meta-data/placement/availability-zone).${EFS_ID}.efs.$REGION.amazonaws.com:/ /shared efs _netdev,noresvport,tls,iam 0 0" >> /etc/fstab
mount -a

# Add spack-users group
groupadd spack-users -g 4000

# change to using ad user login, this is no longer needed 
#/shared/copy_users.sh

#fix the sssd script so getent passws command can find the domain user
#This line allows the users to login without the domain name
sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' /etc/sssd/sssd.conf
#This line configure sssd to create the home directories in the shared folder
sed -i 's/fallback_homedir = \/home\/%u/fallback_homedir = \/shared\/home\/%u/' -i /etc/sssd/sssd.conf
sleep 1
systemctl restart sssd

cat >> /etc/bashrc << 'EOF'
PATH=$PATH:/shared/software/bin
EOF
