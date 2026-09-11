#!/bin/bash

# Setup environment variables
set -euo pipefail

# Default values
ENV="${ENV:-dev}"
CONFIG_FILE="${CONFIG_FILE:-./.configs/${ENV}.env}"

# Usage function
usage() {
    echo "Usage: ENV=<environment> ./deploy.sh"
    echo "  or"
    echo "  CONFIG_FILE=<path-to-config> ./deploy.sh"
    echo ""
    echo "Examples:"
    echo "  ENV=prod ./deploy.sh"
    echo "  CONFIG_FILE=./.configs/custom.env ./deploy.sh"
    echo ""
    echo "Available environments (if using ENV):"
    ls -1 .configs/*.env 2>/dev/null | xargs -n1 basename | sed 's/.env$//' | sed 's/^/  /'
    exit 1
}


# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo ""
    usage
fi

# Source the configuration file
echo "Loading configuration from: $CONFIG_FILE"
# shellcheck disable=SC1090
source "$CONFIG_FILE"

# Validate required parameters
REQUIRED_PARAMS=(
    "STACK_NAME"
    "VPC"
    "PUBLIC_SUBNETS"
    "PRIVATE_SUBNETS"
    "AD_ADMIN_SECRET_ARN"
    "LDAP_NLB_ENDPOINT"
    "EFS_FILESYSTEM_ID"
    "EFS_FILESYSTEM_ARN"
    "BRANCH"
    "SLURM_VERSION"
)

for param in "${REQUIRED_PARAMS[@]}"; do
    if [[ -z "${!param:-}" ]]; then
        echo "Error: Required parameter $param is not set"
        exit 1
    fi
done

aws cloudformation deploy \
--template-file assets/cloudformation/ood.yml \
--stack-name $STACK_NAME \
--capabilities CAPABILITY_NAMED_IAM \
--tags ood:EnvironmentName=srp \
--disable-rollback \
--parameter-overrides \
    VPC="$VPC" \
    PublicSubnets="$PUBLIC_SUBNETS" \
    PrivateSubnets="$PRIVATE_SUBNETS" \
    LoadBalancerLogBucket="${LOAD_BALANCER_LOG_BUCKET:-}" \
    PCSClusterSecurityGroup="${PCS_CLUSTER_SECURITY_GROUP:-}" \
    SlurmAccountingDBSecret="${SLURM_ACCOUNTING_DB_SECRET:-}" \
    SlurmAccountingDBSecretPassword="${SLURM_ACCOUNTING_DB_SECRET_PASSWORD:-}" \
    SlurmAccountingDBSecurityGroup="${SLURM_ACCOUNTING_DB_SECURITY_GROUP:-}" \
    ADAdministratorSecret="$AD_ADMIN_SECRET_ARN" \
    LDAPNLBEndPoint="$LDAP_NLB_ENDPOINT" \
    TopLevelDomain="$TOP_LEVEL_DOMAIN" \
    DomainName="$DOMAIN_NAME" \
    WebsiteDomainName="${WEBSITE_DOMAIN_NAME:-}" \
    HostedZoneId="${HOSTED_ZONE_ID:-}" \
    EFSFileSystemId="$EFS_FILESYSTEM_ID" \
    EFSFileSystemArn="$EFS_FILESYSTEM_ARN" \
    MungeKeySecretArn="${MUNGE_KEY_SECRET_ARN:-}" \
    Branch="$BRANCH" \
    SlurmVersion="$SLURM_VERSION"
