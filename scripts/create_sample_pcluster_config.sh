#!/bin/bash

# this script creates a sample parallelcluster config file to work with your OOD environment. 
# It needs to read outputs from your OOD stack you already deployed. So you need to have the AWS_PROFILE or access key environment variables set
# The cluster will have two partitions defined, one for general workload, one for interactive desktop. 
# Please update your 
export STACK_NAME="OpenOnDemand"
export SSH_KEY='<your SSH_KEY name>'


export REGION="us-east-1"
export DOMAIN_1="rc"
export DOMAIN_2="local"

export OOD_STACK=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION )


export AD_SECRET_ARN=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ADAdministratorSecretARN") | .OutputValue')
export SUBNET=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="PrivateSubnet1") | .OutputValue')
export HEAD_SG=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="HeadNodeSecurityGroup") | .OutputValue')
export HEAD_POLICY=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="HeadNodeIAMPolicyArn") | .OutputValue')
export COMPUTE_SG=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ComputeNodeSecurityGroup") | .OutputValue')
export COMPUTE_POLICY=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ComputeNodeIAMPolicyArn") | .OutputValue')
export BUCKET_NAME=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ClusterConfigBucket") | .OutputValue')
export LDAP_ENDPOINT=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="LDAPNLBEndPoint") | .OutputValue')


cat << EOF > ../pcluster-config.yml 
HeadNode:
  InstanceType: c5.large
  Ssh:
    KeyName: $SSH_KEY
  Networking:
    SubnetId: $SUBNET
    AdditionalSecurityGroups:
      - $HEAD_SG
  LocalStorage:
    RootVolume:
      VolumeType: gp3
      Size: 50
  Iam:
    AdditionalIamPolicies:
      - Policy: arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      - Policy: arn:aws:iam::aws:policy/AmazonS3FullAccess
      - Policy: $HEAD_POLICY
  CustomActions:
    OnNodeConfigured:
      Script: >-
        s3://$BUCKET_NAME/pcluster_head_node.sh
      Args:
        - $STACK_NAME
Scheduling:
  Scheduler: slurm
  SlurmQueues:
    - Name: general
      AllocationStrategy: lowest-price
      ComputeResources:
        - Name: general-cr
          Instances:
            - InstanceType: c5n.large
          MinCount: 0
          MaxCount: 4
      Networking:
        SubnetIds:
          - $SUBNET
        AdditionalSecurityGroups:
          - $COMPUTE_SG
      ComputeSettings:
        LocalStorage:
          RootVolume:
            VolumeType: gp3
            Size: 50
      CustomActions:
        OnNodeConfigured:
          Script: >-
            s3://$BUCKET_NAME/pcluster_worker_node.sh
          Args:
            - $STACK_NAME
      Iam:
        AdditionalIamPolicies:
          - Policy: >-
              $COMPUTE_POLICY
    - Name: desktop
      AllocationStrategy: lowest-price
      ComputeResources:
        - Name: desktop-cr
          Instances:
            - InstanceType: c5n.2xlarge
          MinCount: 0
          MaxCount: 10
      Networking:
        SubnetIds:
          - $SUBNET
        AdditionalSecurityGroups:
          - $COMPUTE_SG
      ComputeSettings:
        LocalStorage:
          RootVolume:
            VolumeType: gp3
            Size: 50
      CustomActions:
        OnNodeConfigured:
          Script: >-
            s3://$BUCKET_NAME/pcluster_worker_node_desktop.sh
          Args:
            - $STACK_NAME
      Iam:
        AdditionalIamPolicies:
          - Policy: >-
              $COMPUTE_POLICY
  SlurmSettings: {}
Region: $REGION
Image:
  Os: alinux2
DirectoryService:
  DomainName: $DOMAIN_1.$DOMAIN_2
  DomainAddr: $LDAP_ENDPOINT
  PasswordSecretArn: $AD_SECRET_ARN
  DomainReadOnlyUser: cn=Admin,ou=Users,ou=$DOMAIN_1,dc=$DOMAIN_1,dc=$DOMAIN_2
EOF