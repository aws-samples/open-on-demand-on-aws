#!/bin/bash

# this script creates a sample parallelcluster config file to work with your OOD environment.
# It needs to read outputs from your OOD stack you already deployed. So you need to have the AWS_PROFILE or access key environment variables set
# The cluster will have two partitions defined, one for general workload, one for interactive desktop.
# Please update your
export STACK_NAME=$1

if [ -z "$STACK_NAME" ]; then
  # show error and exit
  echo "Error: Stack name is required"
  exit 1
fi

export REGION=${2:-"us-east-1"}
export AD_DOMAIN=${3:-"DC=hpclab,DC=local"}
PCLUSTER_FILENAME="pcluster-config.yml"

# Generate help 
if [ "$1" == "--help" ]; then
  echo "Usage: $0 <stack-name> [region] [domain1] [domain2]"
  echo "  stack-name: The name of the stack you deployed"
  echo "  region: The region of the stack you deployed"
  echo "  ad_domain: The LDAP DN (e.g. DC=hpclab,DC=local)"
  exit 0
fi

echo "[-] Checking if stack '$STACK_NAME' exists in region '$REGION'..."
if ! aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &>/dev/null ; then
    echo "Error: Failed to describe stack '$STACK_NAME' in region '$REGION'. Please check your stack name and region."
    exit 1
fi

echo "[-] Reading outputs from stack '$STACK_NAME' in region '$REGION'..."
export OOD_STACK=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION) 
export AD_SECRET_ARN=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ADAdministratorSecretARN") | .OutputValue')
export SUBNETS=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="PrivateSubnets") | .OutputValue')
export HEAD_SG=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="HeadNodeSecurityGroup") | .OutputValue')
export HEAD_POLICY=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="HeadNodeIAMPolicyArn") | .OutputValue')
export COMPUTE_SG=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ComputeNodeSecurityGroup") | .OutputValue')
export COMPUTE_POLICY=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ComputeNodeIAMPolicyArn") | .OutputValue')
export EFS_CLIENT_SG=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="EfsClientSecurityGroup") | .OutputValue')
export BUCKET_NAME=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ClusterConfigBucket") | .OutputValue')
export LDAP_ENDPOINT=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="LDAPNLBEndPoint") | .OutputValue')
export MUNGEKEY_SECRET_ID=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="MungeKeySecretId") | .OutputValue')
export SHARED_FILESYSTEMID=$(echo "$OOD_STACK" | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="EFSMountId") | .OutputValue')

RDS_SECRET_ID=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="SlurmAccountingDBSecret") | .OutputValue')
export RDS_SECRET=$(aws secretsmanager --region $REGION get-secret-value --secret-id $RDS_SECRET_ID --query SecretString --output text)
export RDS_USER=$(echo $RDS_SECRET | jq -r ".username")
export RDS_PASSWORD=$(echo $RDS_SECRET | jq -r ".password")
export RDS_ENDPOINT=$(echo $RDS_SECRET | jq -r ".host")
export RDS_PORT=$(echo $RDS_SECRET | jq -r ".port")
export RDS_DBNAME=$(echo $RDS_SECRET | jq -r ".dbname")
export SLURM_ACCOUNTING_DB_SECRET_ARN=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="SlurmAccountingDBSecretPassword") | .OutputValue')

cat << EOF 
[+] Using the following values to generate $PCLUSTER_FILENAME
  DOMAIN_1                    $DOMAIN_1
  DOMAIN_2                    $DOMAIN_2
  STACK_NAME                  $STACK_NAME
  REGION                      $REGION
  AD_SECRET_ARN               $AD_SECRET_ARN
  SUBNETS                     $SUBNETS
  HEAD_SG                     $HEAD_SG
  HEAD_POLICY                 $HEAD_POLICY
  COMPUTE_SG                  $COMPUTE_SG
  COMPUTE_POLICY              $COMPUTE_POLICY
  BUCKET_NAME                 $BUCKET_NAME
  LDAP_ENDPOINT               $LDAP_ENDPOINT
  MUNGKEY_SECRET_ID           $MUNGEKEY_SECRET_ID
EOF

# Split the subnet string into an array
IFS=',' read -r -a subnets <<< "$SUBNETS"
SUBNET_LIST=$(
for subnet in "${subnets[@]}"; do
  cat <<EOF
          - $subnet
EOF
done
)

echo "[-] Buildng $PCLUSTER_FILENAME..."
cat << EOF > $PCLUSTER_FILENAME
HeadNode:
  InstanceType: c5.large
  Networking:
    SubnetId: ${subnets[0]}
    AdditionalSecurityGroups:
      - $HEAD_SG
      - $EFS_CLIENT_SG
  LocalStorage:
    RootVolume:
      VolumeType: gp3
      Size: 50
  Iam:
    AdditionalIamPolicies:
      - Policy: arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      - Policy: arn:aws:iam::aws:policy/AmazonS3FullAccess
      - Policy: arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess
      - Policy: $HEAD_POLICY
  CustomActions:
    OnNodeConfigured:
      Script: >-
        s3://$BUCKET_NAME/pcluster_head_node.sh
      Args:
        - $STACK_NAME
Scheduling:
  Scheduler: slurm
  SlurmSettings:
    MungeKeySecretArn: $MUNGEKEY_SECRET_ID
    Database:
      Uri: $RDS_ENDPOINT:$RDS_PORT
      UserName: $RDS_USER
      PasswordSecretArn: $SLURM_ACCOUNTING_DB_SECRET_ARN
      DatabaseName: $RDS_DBNAME
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
EOF
for subnet in "${subnets[@]}"; do
cat << EOF >> $PCLUSTER_FILENAME
          - $subnet
EOF
done

cat << EOF >> $PCLUSTER_FILENAME
        AdditionalSecurityGroups:
          - $COMPUTE_SG
          - $EFS_CLIENT_SG
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
          - Policy: $COMPUTE_POLICY
          - Policy: arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess
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
EOF
for subnet in "${subnets[@]}"; do
cat << EOF >> $PCLUSTER_FILENAME
          - $subnet
EOF
done

AD_OU=$(echo $AD_DOMAIN | sed 's/DC=\([^,]*\).*/\1/')

cat << EOF >> $PCLUSTER_FILENAME
        AdditionalSecurityGroups:
          - $COMPUTE_SG
          - $EFS_CLIENT_SG
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
          - Policy: $COMPUTE_POLICY
          - Policy: arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess
LoginNodes:
  Pools:
    - Name: login
      Count: 1
      InstanceType: c5.large
      Networking:
        SubnetIds: 
          - ${subnets[0]}
        AdditionalSecurityGroups:
          - $COMPUTE_SG
          - $EFS_CLIENT_SG
      CustomActions:
        OnNodeConfigured:
          Script: >-
            s3://$BUCKET_NAME/configure_login_nodes.sh
          Args:
            - $STACK_NAME
      Iam:
        AdditionalIamPolicies:
          - Policy: arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
          - Policy: arn:aws:iam::aws:policy/AmazonS3FullAccess
          - Policy: arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
          - Policy: arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess
SharedStorage:
  - MountDir: /shared
    Name: shared-storage
    StorageType: Efs
    EfsSettings:
      FileSystemId: ${SHARED_FILESYSTEMID}
Region: $REGION
Image:
  Os: alinux2
DirectoryService:
  DomainName: $AD_DOMAIN
  DomainAddr: ldap://$LDAP_ENDPOINT
  PasswordSecretArn: $AD_SECRET_ARN
  DomainReadOnlyUser: cn=Admin,ou=Users,ou=$AD_OU,$AD_DOMAIN
  AdditionalSssdConfigs:
    override_homedir: /shared/home/%u
    use_fully_qualified_names: False
    ldap_auth_disable_tls_never_use_in_production: true
EOF
