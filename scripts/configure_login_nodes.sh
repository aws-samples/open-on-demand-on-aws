#!/bin/bash

# This script is intended to be run on a login node.
# It configures the login node with the necessary configuration including:
# * munge key
# * EFS mount (/shared)
# * Fixing the fallback_homedir for sssd
# * Modifies the cluster configuration used by Open OnDemand to point to the Login Node NLB
#
#
# Pre-Requisites:
# * The login node must have the following permissions 
#   * ec2:DescribeInstances permission
#   * cloudformation:Describe*
#   
#   * This can be achieved by adding the following policies to the login node
#     Policy: arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
#     Policy: arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess

set -euo pipefail

usage() {
    cat <<EOF
Usage: configure_login_nodes.sh <OOD_STACK_NAME>
EOF
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

echo "[-] Start Configuring login node"
echo "[-] Retrieving required CloudFormation stack configuration"
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
OOD_STACK_NAME=$1
OOD_STACK=$(aws cloudformation describe-stacks --stack-name $OOD_STACK_NAME --region $REGION)
STACK_NAME=$(aws ec2 describe-instances --instance-id=$INSTANCE_ID --region $REGION --query 'Reservations[].Instances[].Tags[?Key==`parallelcluster:cluster-name`].Value' --output text)
EFS_ID=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="EFSMountId") | .OutputValue')
S3_CONFIG_BUCKET=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ClusterConfigBucket") | .OutputValue')
LOGIN_NODE_STACK_NAME=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME  --query "StackResources[?starts_with(LogicalResourceId, 'LoginNodes') && ResourceType=='AWS::CloudFormation::Stack'][PhysicalResourceId]" --region $REGION --output text)
LOGIN_NODE_NLB=$(aws cloudformation describe-stack-resources --stack-name $LOGIN_NODE_STACK_NAME --query "StackResources[?ResourceType=='AWS::ElasticLoadBalancingV2::LoadBalancer'][PhysicalResourceId]" --region $REGION --output text)
LOGIN_NODE_NLB_DNS_NAME=$(aws elbv2 describe-load-balancers --load-balancer-arns $LOGIN_NODE_NLB --query "LoadBalancers[].DNSName" --region $REGION --output text)

echo "[-] Enabling login nodes for ParallelCluster"
echo "[-] s3 config bucket -> '${S3_CONFIG_BUCKET}'"

aws s3 cp s3://$S3_CONFIG_BUCKET/munge.key /etc/munge/munge.key &> /dev/null
chown munge: /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
systemctl restart munge

if [[ ! -d /shared ]]; then
  echo "[-] Configuring EFS -> '$EFS_ID'"
  mkdir /shared
  echo "$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/placement/availability-zone).${EFS_ID}.efs.$REGION.amazonaws.com:/ /shared efs _netdev,noresvport,tls,iam 0 0" >> /etc/fstab
  mount -a
fi

echo "[-] Fixing fallback_homedir"
sed -i 's/fallback_homedir = \/home\/%u/fallback_homedir = \/shared\/home\/%u/' -i /etc/sssd/sssd.conf
systemctl restart sssd


echo "[-] Updating cluster yaml to use Login Node NLB -> '$LOGIN_NODE_NLB_DNS_NAME'"
aws s3 cp s3://$S3_CONFIG_BUCKET/clusters/$STACK_NAME.yml .
sed -i "s/host: .*/host: \"${LOGIN_NODE_NLB_DNS_NAME}\"/" -i $STACK_NAME.yml
aws s3 cp $STACK_NAME.yml s3://$S3_CONFIG_BUCKET/clusters/$STACK_NAME.yml

echo "Finished!"
