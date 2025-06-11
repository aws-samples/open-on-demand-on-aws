#!/bin/bash

set -uo pipefail

# Function to print colored log messages
log() {
    local level=$1
    local message=$2

    case "$level" in
        "INFO")
            echo -e "\e[34m[INFO]\e[0m $message"
            ;;
        "SUCCESS")
            echo -e "\e[32m[SUCCESS]\e[0m $message"
            ;;
        "WARNING")
            echo -e "\e[33m[WARNING]\e[0m $message"
            ;;
        "ERROR")
            echo -e "\e[31m[ERROR]\e[0m $message"
            ;;
        *)
            echo -e "$message"
            ;;
    esac
}

# Function to check if a stack exists
stack_exists() {
    local stack_name=$1
    aws cloudformation describe-stacks --stack-name "$stack_name" >/dev/null 2>&1
}

# Function to get CloudFormation stack outputs
get_stack_output() {
    local stack_name=$1
    local output_key=$2
    output=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" --output text)
    if [ -z "$output" ]; then
        log "ERROR" "Failed to retrieve value for parameter: $output_key"
        exit 1
    fi
    echo "$output"
}

# Function to display help message
display_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --infra-stack NAME          Name of the infra CloudFormation stack (required)"
    echo "  --ood-stack NAME            Name of the ood CloudFormation stack (required)"
    echo "  --region REGION             AWS region to deploy to (optional, defaults to AWS CLI configured region)"
    echo "  --cluster-name NAME         Name of the PCS cluster (optional, defaults to pcs-starter)"
    echo "  --node-architecture ARCH    Processor architecture for nodes (optional, defaults to x86)"
    echo "                              Allowed values: x86, Graviton"
    echo "  --slurm-version VERSION     Version of Slurm to use (optional, defaults to 24.11)"
    echo "  --host-mount-point PATH     EFS Mount path to use on the PCS Cluster nodes (optional, defaults to /shared)"
    echo "  --branch BRANCH             Branch of the Open On Demand on AWS repository to use (optional, defaults to main)"
    echo "  --help                      Display this help message"
    echo
    echo "Example:"
    echo "  $0 --infra-stack infra-stack --ood-stack ood --cluster-name my-pcs-cluster --node-architecture x86 --region us-east-1"
}

# Set Default values
REGION="${AWS_REGION:-}" # Default to AWS_REGION if populated   
CLUSTER_NAME="pcs-starter"
NODE_ARCHITECTURE="x86"
SLURM_VERSION="24.11"
HOST_MOUNT_POINT="/shared"
BRANCH="main"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log "ERROR" "AWS CLI is not installed"
    exit 1
fi


# Parse named parameters
while [[ $# -gt 0 ]]; do
    case $1 in
        --infra-stack)
            INFRA_STACK="$2"
            shift 2
            ;;
        --ood-stack)
            OOD_STACK="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --node-architecture)
            NODE_ARCHITECTURE="$2"
            shift 2
            ;;
        --slurm-version)
            SLURM_VERSION="$2"
            shift 2
            ;;
        --host-mount-point)
            HOST_MOUNT_POINT="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --help)
            display_help
            exit 0
            ;;
        *)
            log "ERROR" "Unknown parameter: $1"
            display_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "${INFRA_STACK:-}" ]; then
    log "ERROR" "--infra-stack parameter is required"
    display_help
    exit 1
fi

if [ -z "${OOD_STACK:-}" ]; then
    log "ERROR" "--ood-stack parameter is required"
    display_help
    exit 1
fi

if [ -z "${REGION:-}" ]; then
    REGION=$(aws configure get region)
    if [ -z "$REGION" ]; then
        log "ERROR" "AWS region not specified and not found in AWS CLI configuration"
        display_help
        exit 1
    fi
fi

# Retrieve OOD_STACK parameter for SlurmVersion
SLURM_VERSION=$(aws cloudformation describe-stacks --stack-name $OOD_STACK --query "Stacks[0].Parameters[?ParameterKey=='SlurmVersion'].ParameterValue" --output text)
if [[ "$SLURM_VERSION" < "24.11.5" ]]; then
    log "ERROR" "Slurm version must be 24.11.5 or higher"
    exit 1
fi

log "INFO" "Deploying PCS Cluster using outputs from stack: '$INFRA_STACK' and '$OOD_STACK' in region: '$REGION'"

# Check if the infrastructure stack exists
if ! stack_exists "$INFRA_STACK"; then
    log "ERROR" "Stack $INFRA_STACK does not exist"
    exit 1
fi

if ! stack_exists "$OOD_STACK"; then
    log "ERROR" "Stack $OOD_STACK does not exist"
    exit 1
fi

# Get required outputs from the infrastructure stack
log "INFO" "Getting CloudFormation outputs..."

VPC=$(get_stack_output "$INFRA_STACK" "VPCId")
if [ -z "$VPC" ]; then
    log "ERROR" "VPC is null"
    exit 1
fi

PUBLIC_SUBNETS=$(get_stack_output "$INFRA_STACK" "PublicSubnets")
PUBLIC_SUBNET=$(echo "$PUBLIC_SUBNETS" | cut -d',' -f1)
if [ -z "$PUBLIC_SUBNET" ]; then
    log "ERROR" "PublicSubnets is null"
    exit 1
fi

PRIVATE_SUBNETS=$(get_stack_output "$INFRA_STACK" "PrivateSubnets")
PRIVATE_SUBNET=$(echo "$PRIVATE_SUBNETS" | cut -d',' -f1)
if [ -z "$PRIVATE_SUBNET" ]; then
    log "ERROR" "PrivateSubnets is null"
    exit 1
fi

CLUSTER_CONFIG_BUCKET=$(get_stack_output "$OOD_STACK" "ClusterConfigBucket")
if [ -z "$CLUSTER_CONFIG_BUCKET" ]; then
    log "ERROR" "ClusterConfigBucket is null"
    exit 1
fi

CLUSTER_SECURITY_GROUP_ID=$(get_stack_output "$INFRA_STACK" "HPCClusterSecurityGroup")
if [ -z "$CLUSTER_SECURITY_GROUP_ID" ]; then
    log "ERROR" "ClusterSecurityGroupId is null"
    exit 1
fi

EFS_FILESYSTEM_ID=$(get_stack_output "$OOD_STACK" "EFSMountId")
if [ -z "$EFS_FILESYSTEM_ID" ]; then
    log "ERROR" "EFSFileSystemId is null"
    exit 1
fi

EFS_FILESYSTEM_SECURITY_GROUP_ID=$(get_stack_output "$OOD_STACK" "EfsClientSecurityGroup")
if [ -z "$EFS_FILESYSTEM_SECURITY_GROUP_ID" ]; then
    log "ERROR" "EfsFilesystemSecurityGroupId is null"
    exit 1
fi

TOP_LEVEL_DOMAIN=$(get_stack_output "$INFRA_STACK" "TopLevelDomain")
if [ -z "$TOP_LEVEL_DOMAIN" ]; then
    log "ERROR" "TopLevelDomain is null"
    exit 1
fi

DOMAIN_NAME=$(get_stack_output "$INFRA_STACK" "DomainName")
if [ -z "$DOMAIN_NAME" ]; then
    log "ERROR" "DomainName is null"
    exit 1
fi

AD_ADMINISTRATOR_SECRET=$(get_stack_output "$INFRA_STACK" "ADAdministratorSecretARN")
if [ -z "$AD_ADMINISTRATOR_SECRET" ]; then
    log "ERROR" "ADAdministratorSecretARN is null"
    exit 1
fi

LDAP_URI=$(get_stack_output "$INFRA_STACK" "LDAPNLBEndPoint")
if [ -z "$LDAP_URI" ]; then
    log "ERROR" "LDAPNLBEndPoint is null"
    exit 1
fi

STACK_NAME="${CLUSTER_NAME}"
BIND_DN="CN=Admin,OU=Users,OU=${DOMAIN_NAME},DC=${DOMAIN_NAME},DC=${TOP_LEVEL_DOMAIN}"
LDAP_SEARCH_BASE="DC=${DOMAIN_NAME},DC=${TOP_LEVEL_DOMAIN}"
PCS_STARTER_TEMPLATE="https://raw.githubusercontent.com/aws-samples/open-on-demand-on-aws/refs/heads/${BRANCH}/assets/cloudformation/pcs-starter.yml"

# Deploy PCS Cluster stack
log "INFO" "PCS Cluster deployment parameters:"
log "INFO" "--------------------------------------------------------"
log "INFO" "VPC: $VPC"
log "INFO" "Public Subnets: $PUBLIC_SUBNETS"
log "INFO" "Private Subnets: $PRIVATE_SUBNETS"
log "INFO" "Cluster Security Group ID: $CLUSTER_SECURITY_GROUP_ID"
log "INFO" "EFS Mount Point: $HOST_MOUNT_POINT"
log "INFO" "EFS FileSystem ID: $EFS_FILESYSTEM_ID"
log "INFO" "EFS FileSystem Security Group ID: $EFS_FILESYSTEM_SECURITY_GROUP_ID"
log "INFO" "Cluster Name: $CLUSTER_NAME"
log "INFO" "Domain Name: $DOMAIN_NAME"
log "INFO" "Top Level Domain: $TOP_LEVEL_DOMAIN"
log "INFO" "AD Administrator Secret: $AD_ADMINISTRATOR_SECRET"
log "INFO" "LDAP NLB End Point: $LDAP_URI"


log "INFO" "Downloading PCS Starter template from $PCS_STARTER_TEMPLATE"
curl --silent --output pcs-starter.yml $PCS_STARTER_TEMPLATE

log "INFO" "Deploying PCS Cluster"
aws cloudformation deploy \
    --template-file pcs-starter.yml \
    --stack-name $STACK_NAME \
    --parameter-overrides \
        VPC="$VPC" \
        PublicSubnet="$PUBLIC_SUBNET" \
        PrivateSubnet="$PRIVATE_SUBNET" \
        HPCClusterSecurityGroupId="$CLUSTER_SECURITY_GROUP_ID" \
        HostMountPoint="$HOST_MOUNT_POINT" \
        EFSFileSystemId="$EFS_FILESYSTEM_ID" \
        EfsFilesystemSecurityGroupId="$EFS_FILESYSTEM_SECURITY_GROUP_ID" \
        SlurmVersion="$SLURM_VERSION" \
        ClusterName="$CLUSTER_NAME" \
        DomainName="$DOMAIN_NAME" \
        TopLevelDomain="$TOP_LEVEL_DOMAIN" \
        BindDN="$BIND_DN" \
        LDAPSearchBase="$LDAP_SEARCH_BASE" \
        ClusterConfigBucket="$CLUSTER_CONFIG_BUCKET" \
        LDAPUri="$LDAP_URI" \
        BindPasswordSecretArn="$AD_ADMINISTRATOR_SECRET" \
        NodeArchitecture="$NODE_ARCHITECTURE" \
        SlurmVersion="$SLURM_VERSION" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

if [ $? -ne 0 ]; then
    log "ERROR" "PCS Cluster deployment failed"
    exit 1
fi

log "SUCCESS" "PCS Cluster deployment completed successfully!"
echo
