# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#!/bin/bash

yum -y -q install sssd realmd krb5-workstation samba-common-tools jq mysql amazon-efs-utils
# Get OOD Stack data
OOD_STACK_NAME=$1
REGION=$(curl http://169.254.169.254/latest/meta-data/placement/region)

OOD_STACK=$(aws cloudformation describe-stacks --stack-name $OOD_STACK_NAME --region $REGION )


S3_CONFIG_BUCKET=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ClusterConfigBucket") | .OutputValue')
EFS_ID=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="EFSMountId") | .OutputValue')

# OOD_SECRET_ID=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="SecretId") | .OutputValue')
# AD_PASSWORD_SECRET=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ADAdministratorSecretARN") | .OutputValue')

# # export AD_SECRET=$(aws secretsmanager --region $REGION get-secret-value --secret-id $OOD_SECRET_ID --query SecretString --output text)
# export DOMAIN_NAME=$(echo $AD_SECRET | jq -r ".DomainName")
# export TOP_LEVEL_DOMAIN=$(echo $AD_SECRET | jq -r ".TopLevelDomain")

# export AD_PASSWORD=$(aws secretsmanager --region $REGION get-secret-value --secret-id $AD_PASSWORD_SECRET --query SecretString --output text)

# # Join head node to the domain; PCluster doesn't do this by default
# echo $AD_PASSWORD | realm join -v -U Administrator $DOMAIN_NAME.$TOP_LEVEL_DOMAIN --install=/

# Copy Common Munge Key
aws s3 cp s3://$S3_CONFIG_BUCKET/munge.key /etc/munge/munge.key
chown munge: /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
systemctl restart munge

# Add entry for fstab so mounts on restart
mkdir /shared
echo "$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone).${EFS_ID}.efs.$REGION.amazonaws.com:/ /shared efs _netdev,noresvport,tls,iam 0 0" >> /etc/fstab
mount -a

# Add spack-users group
groupadd spack-users -g 4000
/shared/copy_users.sh