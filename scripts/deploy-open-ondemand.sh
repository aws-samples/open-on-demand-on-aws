#!/bin/bash

# This script deploys Open OnDemand on AWS using CloudFormation.

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

# Function to check if a stack exists
stack_exists() {
    local stack_name=$1
    aws cloudformation describe-stacks --stack-name "$stack_name" >/dev/null 2>&1
}

# Function to display help message
display_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --infra-stack NAME          Name of the infra CloudFormation stack (required)"
    echo "  --slurm-db-stack NAME       Name of the slurm-db CloudFormation stack (optional)"
    echo "  --region REGION             AWS region to deploy to (optional, defaults to AWS CLI configured region)"
    echo "  --branch BRANCH             Git branch to use for deployment (optional, defaults to 'main')"
    echo "  --slurm-version VERSION     Slurm version to deploy (optional, defaults to '24.11.5')"
    echo "  --help                      Display this help message"
    echo
    echo "Example:"
    echo "  $0 --infra-stack infra-stack [--slurm-db-stack slurm-db-stack] [--region us-east-1] [--branch main] [--slurm-version 24.11.5]"
}

# Set default branch to 'main'
BRANCH="main"
SLURM_VERSION="24.11.5"  # Latest version compatible with PCS
PCLUSTER_SLURM_VERSION="24.05.7" # Latest version compatible with ParallelCluster 3.13.0

REGION="${AWS_REGION:-}" # Default to AWS_REGION if populated   
SLURM_ACCOUNTING_DB_SECRET=""
SLURM_ACCOUNTING_DB_SECURITY_GROUP=""
SLURM_ACCOUNTING_DB_PASSWORD=""
PCS_CLUSTER_SECURITY_GROUP=""

# Parse named parameters
while [[ $# -gt 0 ]]; do
    case $1 in
        --infra-stack)
            INFRA_STACK="$2"
            shift 2
            ;;
        --slurm-db-stack)
            SLURM_DB_STACK="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --slurm-version)
            SLURM_VERSION="$2"
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

if [ -z "${REGION:-}" ]; then
    REGION=$(aws configure get region)
    if [ -z "$REGION" ]; then
        log "ERROR" "AWS region not specified and not found in AWS CLI configuration"
        display_help
        exit 1
    fi
fi

log "INFO" "Deploying Open OnDemand using outputs from stack: '$INFRA_STACK' in region: '$REGION'"

# Check if the infrastructure stack exists
if ! stack_exists "$INFRA_STACK"; then
    log "ERROR" "Stack $INFRA_STACK does not exist"
    exit 1
fi

# Get required outputs from the infrastructure stack
log "INFO" "Getting CloudFormation outputs..."

AD_ADMIN_SECRET_ARN=$(get_stack_output "$INFRA_STACK" "ADAdministratorSecretARN")
if [ -z "$AD_ADMIN_SECRET_ARN" ]; then
    log "ERROR" "ADAdministratorSecretARN is null"
    exit 1
fi

LDAP_NLB_ENDPOINT=$(get_stack_output "$INFRA_STACK" "LDAPNLBEndPoint")
if [ -z "$LDAP_NLB_ENDPOINT" ]; then
    log "ERROR" "LDAPNLBEndPoint is null"
    exit 1
fi

VPC=$(get_stack_output "$INFRA_STACK" "VPCId")
if [ -z "$VPC" ]; then
    log "ERROR" "VPC is null"
    exit 1
fi

PUBLIC_SUBNETS=$(get_stack_output "$INFRA_STACK" "PublicSubnets")
if [ -z "$PUBLIC_SUBNETS" ]; then
    log "ERROR" "PublicSubnets is null"
    exit 1
fi

PRIVATE_SUBNETS=$(get_stack_output "$INFRA_STACK" "PrivateSubnets")
if [ -z "$PRIVATE_SUBNETS" ]; then
    log "ERROR" "PrivateSubnets is null"
    exit 1
fi

PCS_CLUSTER_SECURITY_GROUP=$(get_stack_output "$INFRA_STACK" "PCSClusterSecurityGroupId")

LOAD_BALANCER_LOG_BUCKET=$(get_stack_output "$INFRA_STACK" "LoadBalancerLogBucket")
if [ -z "$LOAD_BALANCER_LOG_BUCKET" ]; then
    log "ERROR" "LoadBalancerLogBucket is null"
    exit 1
fi

if [ -z "${SLURM_DB_STACK:-}" ]; then
    log "INFO" "Slurm Accounting DB stack not specified, skipping..."
else
    if ! stack_exists "$SLURM_DB_STACK"; then
        log "ERROR" "Stack $SLURM_DB_STACK does not exist"
        exit 1
    fi

    # Verify that SLURM_DB_STACK deployment is complete
    stack_status=$(aws cloudformation describe-stacks --stack-name "$SLURM_DB_STACK" --query 'Stacks[0].StackStatus' --output text)
    if [ "$stack_status" != "CREATE_COMPLETE" ] && [ "$stack_status" != "UPDATE_COMPLETE" ]; then
        log "ERROR" "Stack $SLURM_DB_STACK is not in a complete state. Current status: '$stack_status'.  Wait for stack to be in a complete state before continuing..."
        exit 1
    fi

    SLURM_ACCOUNTING_DB_SECRET=$(get_stack_output "$SLURM_DB_STACK" "DBSecretId")
    if [ -z "$SLURM_ACCOUNTING_DB_SECRET" ]; then
        log "ERROR" "SlurmAccountingDBSecret is null"
        exit 1
    fi

    SLURM_ACCOUNTING_DB_SECURITY_GROUP=$(get_stack_output "$SLURM_DB_STACK" "DBSecurityGroup")
    if [ -z "$SLURM_ACCOUNTING_DB_SECURITY_GROUP" ]; then
        log "ERROR" "SlurmAccountingDBSecurityGroup is null"
        exit 1
    fi

    SLURM_ACCOUNTING_DB_PASSWORD=$(get_stack_output "$SLURM_DB_STACK" "DBSecretPassword")
    if [ -z "$SLURM_ACCOUNTING_DB_PASSWORD" ]; then
        log "ERROR" "SlurmAccountingDBPassword is null"
        exit 1
    fi
fi

# Deploy Open OnDemand stack
log "INFO" "Open OnDemand deployment parameters:"
log "INFO" "--------------------------------------------------------"
log "INFO" "VPC: $VPC"
log "INFO" "Public Subnets: $PUBLIC_SUBNETS"
log "INFO" "Private Subnets: $PRIVATE_SUBNETS"
log "INFO" "PCS Cluster Security Group: $PCS_CLUSTER_SECURITY_GROUP"
log "INFO" "Load Balancer Log Bucket: $LOAD_BALANCER_LOG_BUCKET"
log "INFO" "AD Administrator Secret ARN: $AD_ADMIN_SECRET_ARN"
log "INFO" "LDAP NLB Endpoint: $LDAP_NLB_ENDPOINT"
if [ -n "$SLURM_ACCOUNTING_DB_SECRET" ]; then
    log "INFO" "Slurm Accounting DB Secret: $SLURM_ACCOUNTING_DB_SECRET"
    log "INFO" "Slurm Accounting DB Security Group: $SLURM_ACCOUNTING_DB_SECURITY_GROUP"
    log "INFO" "Slurm Accounting DB Password: $SLURM_ACCOUNTING_DB_PASSWORD"
fi

# Get the ood.yml file from the assets bucket
log "INFO" "Downloading 'ood.yml'"
wget -O ood.yml https://ws-assets-prod-iad-r-iad-ed304a55c2ca1aee.s3.us-east-1.amazonaws.com/c4d84bde-e2c5-44ed-a7ee-1a27e90e2cb2/ood.yml &> /dev/null

log "INFO" "Deploying Open OnDemand on AWS"

aws cloudformation deploy \
    --template-file ood.yml \
    --stack-name ood \
    --parameter-overrides \
        VPC="$VPC" \
        PublicSubnets="$PUBLIC_SUBNETS" \
        PrivateSubnets="$PRIVATE_SUBNETS" \
        LoadBalancerLogBucket="$LOAD_BALANCER_LOG_BUCKET" \
        PCSClusterSecurityGroup="$PCS_CLUSTER_SECURITY_GROUP" \
        SlurmAccountingDBSecret="$SLURM_ACCOUNTING_DB_SECRET" \
        SlurmAccountingDBSecretPassword="$SLURM_ACCOUNTING_DB_PASSWORD" \
        SlurmAccountingDBSecurityGroup="$SLURM_ACCOUNTING_DB_SECURITY_GROUP" \
        ADAdministratorSecret="$AD_ADMIN_SECRET_ARN" \
        LDAPNLBEndPoint="$LDAP_NLB_ENDPOINT" \
        WebsiteDomainName="" \
        HostedZoneId="" \
        EFSFileSystemId="" \
        EFSFileSystemArn="" \
        MungeKeySecretArn="" \
        Branch="$BRANCH" \
        SlurmVersion="$SLURM_VERSION" \
    --capabilities CAPABILITY_IAM

log "SUCCESS" "Open OnDemand deployment completed successfully!"
echo

# Get the URL of the Open OnDemand portal
log "INFO" "Open OnDemand portal URL: $(get_stack_output "ood" "URL")"
