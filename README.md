# 🚀 Open OnDemand on AWS with Parallel Cluster

This reference architecture provides a set of templates for deploying [Open OnDemand (OOD)](https://openondemand.org/) with [AWS CloudFormation](https://aws.amazon.com/cloudformation/) and integration points for both [AWS ParallelCluster](https://aws.amazon.com/hpc/parallelcluster/) and [AWS Parallel Computing Service (AWS PCS)](https://aws.amazon.com/pcs/).

## 🏗️ Architecture

![architecture](images/architecture.png)

The primary components of the solution are:

1. Application load balancer as the entry point to your OOD portal
2. An Auto Scaling Group for the OOD Portal
3. A Microsoft ManagedAD Directory
4. A Network Load Balancer (NLB) to provide a single point of connectivity to Microsoft ManagedAD
5. An Elastic File System (EFS) share for user home directories
6. An Aurora MySQL database to store Slurm Accounting data
7. Automation via Event Bridge to automatically register and deregister ParallelCluster HPC Clusters with OOD

## 🔄 Compatibility

This solution is compatible with the following HPC service(s) from AWS:
* AWS ParallelCluster [v3.13.0](https://github.com/aws/aws-parallelcluster/releases/tag/v3.13.0)
* [AWS Parallel Computing Service (AWS PCS)](https://aws.amazon.com/pcs/)
* Open OnDemand v4.0

## 🚀 Deployment Process

The deployment process involves several key steps to set up Open OnDemand with AWS ParallelCluster or AWS PCS integration. Follow these steps carefully to ensure a successful deployment.

### Prerequisites
- AWS CLI v2 installed and configured with appropriate credentials
- Domain name and hosted zone in Route 53 (required for custom domain setup)
- Basic understanding of AWS ParallelCluster or AWS PCS if planning to integrate HPC clusters
 
### Deployment Options
- [All-in-one deployment](#all-in-one-deployment) (recommended for first-time users, or sandbox environments)
- [Modular deployment](#modular-deployment) (for advanced users)

### All-in-one Deployment

All in one deployment including **infrastructure** and **Open OnDemand**

1. Deploy CloudFormation assets to S3:
   ```bash
   ./deploy-assets.sh
   ```
   This script uploads all required CloudFormation templates and assets to an S3 bucket in your AWS account.

2. Deploy the all-in-one stack [ood_full.yml](assets/cloudformation/ood_full.yml) via CloudFormation.  

| Parameter | Description | Type | Default |
|-----------|-------------|------|---------|
| DomainName | Domain name not including the top level domain | String | hpclab |
| TopLevelDomain | TLD for your domain (i.e. local, com, etc) | String | local |
| WebsiteDomainName | Domain name for world facing website | String | - |
| HostedZoneId | Hosted Zone Id for Route53 Domain | String | - |
| PortalAllowedIPCIDR | IP CIDR for access to the Portal | String | - |
| Branch | Branch of the code to deploy. Only use this when testing changes to the solution | String | main |
| SlurmVersion | Version of slurm to install | String | 24.05.7 |
| DeploymentAssetBucketName | Deployment Asset Bucket Name | String | ood-assets |

> **Note:** `DeploymentAssetBucketName` is the output from step 1 (deploy assets)

### Modular Deployment

**Deploy Stacks individually:**

1. Deploy Infrastructure (*Networking, and Managed Active Directory*): [infra.yml](assets/cloudformation/infra.yml)
2. Deploy Slurm Accounting Database (_only if integrating with ParallelCluster_): [slurm_accounting_db.yml](assets/cloudformation/slurm_accounting_db.yml)
3. Deploy Open OnDemand: [ood.yml](assets/cloudformation/ood.yml)

| Parameter | Description | Default |
|-----------|-------------|---------|
| DomainName | Domain name not including the top level domain | hpclab |
| TopLevelDomain | TLD for your domain (i.e. local, com, etc) | local |
| WebsiteDomainName | Domain name for world facing website | - |
| HostedZoneId | Hosted Zone Id for Route53 Domain | - |
| PortalAllowedIPCIDR | IP CIDR for access to the Portal | - |
| Branch | Branch of the code to deploy. Only use this when testing changes to the solution | main |
| DeploymentAssetBucketName | Deployment Asset Bucket Name | - |
| VPC | VPC for OOD deployment | - |
| PrivateSubnet | Private subnet for OOD deployment | - |
| PublicSubnet | Public subnet for OOD deployment | - |
| BindDN | Bind DN for the directory | CN=Admin,OU=Users,OU=hpclab,DC=hpclab,DC=local |
| LDAPSearchBase | LDAP Search Base | DC=hpclab,DC=local |
| LDAPUri | LDAP URI for Managed AD | - |
| BindPasswordSecretArn | BIND Password Secret ARN for Admin user in Managed AD | - |
| ClusterConfigBucket | S3 Bucket where Cluster Configuration items are stored | - |
| NodeArchitecture | Processor architecture for the login and compute node instances | x86 |
| SlurmVersion | Version of slurm to install.  Select `24.11.5` or greater if using **AWS PCS** | 24.05.7 |
| AccountingPolicyEnforcement | Specify which Slurm accounting policies to enforce | none |


## 🔑 Post Deployment Steps

Once deployed, navigate to the `URL` found in the Open OnDemand stack CloudFormation outputs. A default `admin` user is created as part of the deployment and can be used to validate login works correctly.

| Username | Password |
|----------|----------|
| `Admin`  | Retrieve the secret value from secrets manager. The secret ARN is in the CloudFormation outputs under `ADAdministratorSecretArn` |

## 🖥️ Deploying an integrated ParallelCluster HPC Cluster

The OOD solution is built to integrate with [AWS ParallelCluster](https://docs.aws.amazon.com/parallelcluster/latest/ug/what-is-aws-parallelcluster.html) HPC Cluster can be created and automatically registered with the portal.

To deploy a ParallelCluster refer to [Setting up AWS ParallelCluster](https://docs.aws.amazon.com/parallelcluster/latest/ug/install-v3.html) to get started. This includes (but not limited to):

- Install [AWS ParallelCluster CLI](https://docs.aws.amazon.com/parallelcluster/latest/ug/install-v3-parallelcluster.html)
- Create ParallelCluster [configuration file](https://docs.aws.amazon.com/parallelcluster/latest/ug/cluster-configuration-file-v3.html)

### Create ParallelCluster Configuration

To integrate a ParallelCluster HPC cluster with Open OnDemand, you need to create a ParallelCluster configuration file that defines:

The configuration file serves as the blueprint for your HPC cluster and ensures proper integration with the Open OnDemand portal for job submission and management.

You can either:
- Use the provided script to automatically generate a configuration file (**recommended)**
- Manually create a configuration file following the guidelines below

#### Automatically generate ParallelCluster configuration (recommended)

You can automatically generate a ParallelCluster configuration file using the provided [scripts/create_sample_pcluster_config.sh](scripts/create_sample_pcluster_config.sh) script. This script will create a properly configured [pcluster configuration file](https://docs.aws.amazon.com/parallelcluster/latest/ug/cluster-configuration-file-v3.html) with all the necessary settings for Open OnDemand integration.

**Example to create a `pcluster-config.yml` file:**
```bash
./create_sample_pcluster_config.sh ood
```

**Usage:**
```bash
Usage: ./create_sample_pcluster_config.sh <stack-name> [region] [domain1] [domain2]
  stack-name: The name of the stack you deployed
  region: The region of the stack you deployed
  ad_domain: The LDAP DN (e.g. DC=hpclab,DC=local)
```

#### Manual Cluster Configuration

To create the ParallelCluster [configuration file](https://docs.aws.amazon.com/parallelcluster/latest/ug/cluster-configuration-file-v3.html) refer to the following information:

#### HeadNode
- SubnetId: `PrivateSubnets` from OOD Stack Output
- AdditionalScurityGroups: `HeadNodeSecurityGroup` from CloudFormation Outputs
- AdditionalIAMPolicies: `HeadNodeIAMPolicyArn` from CloudFormation Outputs
- OnNodeConfigured
  - Script: CloudFormation Output for the `ClusterConfigBucket`; in the format `s3://$ClusterConfigBucket/pcluster_head_node.sh`
  - Args: Open OnDemand CloudFormation stack name

#### SlurmQueues
- SubnetId: `PrivateSubnets` from OOD Stack Output
- AdditionalScurityGroups: `ComputeNodeSecurityGroup` from CloudFormation Outputs
- AdditionalIAMPolicies: `ComputeNodeIAMPolicyArn` from CloudFormation Outputs
- OnNodeConfigured
  - Script: CloudFormation Output for the `ClusterConfigBucket`; in the format `s3://$ClusterConfigBucket/pcluster_worker_node.sh`
  - Args: Open OnDemand CloudFormation stack name

#### LoginNode
- OnNodeConfigured
  - Script: CloudFormation Output for the `ClusterConfigBucket`; in the format `s3://$ClusterConfigBucket/configure_login_nodes.sh`
  - Args: Open OnDemand CloudFormation stack name

## 🔒 Optional - Enable pam_slurm_adopt module for ParallelCluster compute nodes

The [pam_slurm_adopt](https://slurm.schedmd.com/pam_slurm_adopt.html) module can be enabled on Compute nodes in ParallelCluster to prevent users from ssh'ing to nodes they do not have a job running.

In your ParallelCluster config, update the following configuration(s):

1. Check if any steps have been launched.

Add the **CustomSlurmSetting** `PrologFlags: "contain"` in the [Scheduling](https://docs.aws.amazon.com/parallelcluster/latest/ug/Scheduling-v3.html) section. Refer to [slurm configuration](https://slurm.schedmd.com/pam_slurm_adopt.html#important) documentation for more details on this slurm setting.

**Example:**
```yaml
SlurmSettings:  
  CustomSlurmSettings:
    - PrologFlags: "contain"
```

2. Ensure compute nodes are exclusively allocated to users.  

Add the **CustomSlurmSetting** `ExclusiveUser: "YES"` in the [SlurmQueues](https://docs.aws.amazon.com/parallelcluster/latest/ug/Scheduling-v3.html#Scheduling-v3-SlurmQueues) section. Refer to [slurm partition configuration](https://slurm.schedmd.com/slurm.conf.html#OPT_ExclusiveUser) for more details.

**Example:**
```yaml
CustomSlurmSettings:
  ExclusiveUser: "YES"
```

3. Add [configure_pam_slurm_adopt.sh](scripts/configure_pam_slurm_adopt.sh) to **OnNodeConfigured** in the [CustomActions](https://docs.aws.amazon.com/parallelcluster/latest/ug/Scheduling-v3.html#Scheduling-v3-SlurmQueues-CustomActions) section.  

**Example:**
```yaml
CustomActions:
  OnNodeConfigured:
    Sequence:
    - Script: s3://$ClusterConfigBucket/pcluster_worker_node.sh
        Args:
        - Open OnDemand CloudFormation stack name
    - Script: s3://$ClusterConfigBucket/configure_pam_slurm_adopt.sh
```

## 🖥️ Enabling Interactive Desktops

**Note**: If you automatically created your ParallelCluster configuration using the recommended approach a `desktop` queue was created for you.

You can enable [interactive desktops](https://osc.github.io/ood-documentation/latest/enable-desktops.html) on the Portal server. This can be enabled by creating a queue in ParallelCluster to be used for the desktop sessions. 

> **Note:** This requires you to have a compute queue with `pcluster_worker_node_desktop.sh` as your `OnNodeConfigured` script.

**Snippet from ParallelCluster config:**
```yaml
CustomActions:
  OnNodeConfigured:
    Script: >-
      s3://{{ClusterConfigBucket}}/pcluster_worker_node_desktop.sh
    Args:
      - {{OOD_STACK_NAME}}
```

- `OOD_STACK_NAME` is the name of your Open OnDemand CloudFormation stack name (e.g. `ood`)
- `ClusterConfigBucket` is the **ClusterConfigBucket** Output from CloudFormation

## ⚙️ Slurm Configuration Management

Slurm configuration can be maintained outside of the Open OnDemand deployment.  

The `ClusterConfigBucket` S3 bucket (available in CloudFormation Outputs) stores Slurm configurations under the `/slurm` prefix. Configuration files that would normally reside in `/etc/slurm` can be uploaded to this prefix, and an EventBridge rule will automatically sync them to the Open OnDemand server.

The following configurations are stored by default:

- [slurm.conf](https://slurm.schedmd.com/slurm.conf.html)

### How to update slurm configuration

To update the slurm configuration on the Open OnDemand server, copy any configuration file(s) to the `ClusterConfigBucket` S3 bucket under the `/slurm` prefix. The configuration will be automatically synced to the Open OnDemand server.

## 🖥️ Deploying an integrated AWS Parallel Computing Service (AWS PCS) cluster

This solution is now compatible with [AWS Parallel Computing Service (AWS PCS)](https://aws.amazon.com/pcs/), which provides a fully managed HPC service that simplifies cluster deployment and management. AWS PCS offers several key benefits:

- **Managed Infrastructure**: AWS handles the underlying infrastructure, including compute, networking, and storage, reducing operational overhead
- **Built-in Security**: Integrated with AWS security services and best practices for HPC workloads
- **Cost Optimization**: Pay only for the compute resources you use with flexible scaling options
- **Simplified Management**: Automated cluster lifecycle management and monitoring through the AWS Management Console
- **Native AWS Integration**: Seamless integration with other AWS services like Amazon FSx for Lustre and Amazon EFS

### Getting Started with AWS PCS

Refer to the following getting started guides:

- Get started with AWS PCS - https://docs.aws.amazon.com/pcs/latest/userguide/getting-started.html
- Get started with AWS CloudFormation and AWS PCS - https://docs.aws.amazon.com/pcs/latest/userguide/get-started-cfn.html
- HPC Recipe for getting started with AWS PCS - [aws-hpc-recipes/recipes/pcs/getting_started](https://github.com/aws-samples/aws-hpc-recipes/tree/main/recipes/pcs/getting_started)
  - This guide includes many helpful CloudFormation templates to get started


#### 1. Deploy PCS Getting started stack

**Option 1**: Use [scripts/deploy_pcs.sh](scripts/deploy_pcs.sh) script to deploy [assets/cloudformation/pcs-starter.yml](assets/cloudformation/pcs-starter.yml).  This script is a helper utility to help deploy the `pcs-starter` template by pulling the parameters from CloudFormation outputs.

1.  Open AWS CloudShell
2.  Download `deploy_pcs.sh`

```bash
curl -o deploy_pcs.sh https://raw.githubusercontent.com/aws-samples/open-on-demand-on-aws/refs/heads/main/scripts/deploy_pcs.sh
```
3. Make the script executable:

```bash
chmod +x deploy_pcs.sh
```

4. Run the deployment script:

```bash
./deploy_pcs.sh --infra-stack <infra-stack-name> --ood-stack <ood-stack-name>
```

**Script help**
```
Usage: ./scripts/deploy_pcs.sh [options]

Options:
  --infra-stack NAME          Name of the infra CloudFormation stack (required)
  --ood-stack NAME            Name of the ood CloudFormation stack (required)
  --region REGION             AWS region to deploy to (optional, defaults to AWS CLI configured region)
  --cluster-name NAME         Name of the PCS cluster (optional, defaults to pcs-starter)
  --node-architecture ARCH    Processor architecture for nodes (optional, defaults to x86)
                              Allowed values: x86, Graviton
  --slurm-version VERSION     Version of Slurm to use (optional, defaults to 24.11)
  --host-mount-point PATH     Mount path on the host (optional, defaults to /shared)
  --branch BRANCH             Branch of the Open On Demand on AWS repository to use (optional, defaults to main)
  --help                      Display this help message

Example:
  ./scripts/deploy_pcs.sh --infra-stack infra-stack --ood-stack ood --cluster-name my-pcs-cluster --node-architecture x86 --region us-east-1
```

**Option 2**: Manually deploy [assets/cloudformation/pcs-starter.yml](assets/cloudformation/pcs-starter.yml) via **CloudFormation**

To deploy the CloudFormation template manually:

1. Open the AWS CloudFormation console
2. Click "Create stack" and select "With new resources (standard)"
3. Under "Template source", select "Upload a template file" and upload `pcs-starter.yml`
4. Click "Next"
5. Enter a stack name (e.g., `pcs-starter`)
6. Configure the following parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| VPC | VPC for PCS cluster | - |
| PrivateSubnet | Private subnet | - |
| PublicSubnet | Public subnet | - |
| ClusterName | Name of the PCS cluster | - |
| HPCClusterSecurityGroupId | Security group for PCS cluster controller and nodes | - |
| EFSFileSystemId | EFS file system ID | - |
| EfsFilesystemSecurityGroupId | Security group for EFS filesystem | - |
| NodeArchitecture | Processor architecture for the login and compute node instances | x86 |
| SlurmVersion | Version of Slurm to use | 24.11 |
| DomainName | Domain name | hpclab |
| TopLevelDomain | Top level domain | local |
| ADAdministratorSecret | AD Administrator Secret | - |
| BindDN | Bind DN for the directory | CN=Admin,OU=Users,OU=hpclab,DC=hpclab,DC=local |
| LDAPSearchBase | LDAP Search Base | DC=hpclab,DC=local |
| HostMountPoint | Mount path on the host | /shared |
| ClusterConfigBucket | S3 Bucket where Cluster Configuration items are stored | - |
| LDAPUri | LDAP URI for Managed AD | - |
| BindPasswordSecretArn | BIND Password Secret ARN for Admin user in Managed AD | - |
| AccountingPolicyEnforcement | Specify which Slurm accounting policies to enforce | none |

7. Click "Next" to configure stack options
8. Click "Next" to review
9. Check the acknowledgment box and click "Create stack"

#### 2. Configure sackd and slurm on Open OnDemand

The [scripts/s3_script_runner.sh](scripts/s3_script_runner.sh) script uses AWS Systems Manager (SSM) to send a command to the Open OnDemand EC2 instance. This command executes a configuration script that sets up both `sackd` and `slurm` services to work with your PCS cluster.

1. Open AWS CloudShell

2. Download `s3_script_runner.sh`

```bash
curl -o s3_script_runner.sh https://raw.githubusercontent.com/aws-samples/open-on-demand-on-aws/refs/heads/main/scripts/s3_script_runner.sh
```

3. Make the script executable:

```bash
chmod +x s3_script_runner.sh
```

4. Run the following command to setup some parameters that will be used later.

Setup parameters needed for SSM Send Command to configure the Open OnDemand instance with PCS cluster settings. These parameters include:

- **CLUSTER_ID**: The ID of the PCS cluster
- **CLUSTER_CONFIG_BUCKET**: The S3 bucket storing cluster configurations
- **INSTANCE_ID**: The EC2 instance ID of the Open OnDemand web portal
- **OOD_STACK**: The CloudFormation stack name for Open OnDemand
- **CLUSTER_NAME**: The name of the workshop cluster

   
```bash
CLUSTER_ID=$(aws cloudformation describe-stacks --stack-name pcs-starter --query "Stacks[0].Outputs[?OutputKey=='ClusterId'].OutputValue" --output text)
CLUSTER_CONFIG_BUCKET=$(aws cloudformation describe-stacks --stack-name ood --query "Stacks[0].Outputs[?OutputKey=='ClusterConfigBucket'].OutputValue" --output text)
INSTANCE_ID=$(aws ec2 describe-instances --filters \
  "Name=tag:ood,Values=webportal-ood" \
  "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
--output text)
OOD_STACK="<INSERT OOD STACK NAME>"
CLUSTER_NAME="pcs-starter"
```

5. Run the `s3_script_runner.sh` script which will trigger an `ssm send-command` request trigger the Open OnDemand ec2 instance to run a script which will configure both `sackd` and `slurm` and integrate it with the PCS cluster.


```bash
COMMAND_ID=$(./s3_script_runner.sh \
  --instance-id "$INSTANCE_ID" \
  --document-name "pcs-starter-S3ScriptRunner" \
  --bucket-name "$CLUSTER_CONFIG_BUCKET" \
  --script-key "configure_ood_for_pcs.sh" \
  --script-args "--ood-stack $OOD_STACK --cluster-name $CLUSTER_NAME --cluster-id $CLUSTER_ID --region $AWS_REGION")
```

This will output the `CommandId` of the command being run (**example below)**

```
ccc5375a-e192-4d36-af57-5dd7a7740f0d
```

1. Inspect the SSM results using the following command to verify the configuration was successful. This command will show the detailed output of the script execution, including:

- Command execution status
- Standard output showing the configuration steps
- Any errors that may have occurred
- Execution timing information

```bash
aws ssm get-command-invocation \
    --command-id $COMMAND_ID \
    --instance-id $INSTANCE_ID
```

Reviewing the result you should see `Status == Success`

## 🔧 Troubleshooting

### Issue submitting jobs after adding a ParallelCluster

There can be errors submitting jobs after integrating OOD w/ParalleCluster due to slurm registering the cluster. Review the logs found in `/var/log/sbatch.log` and check if there are errors related to available clusters.

**Sample log entry:**
```
vbatch: error: No cluster 'sandbox-cluster' known by database.
sbatch: error: 'sandbox-cluster' can't be reached now, or it is an invalid entry for --cluster.  Use 'sacctmgr list clusters' to see available clusters.
```

If this occurs, restart both the `slurmctld` and `slurmdbd` services should be restarted. 

```bash
systemctl restart slurmctld
systemctl restart slurmdbd
```

Once restarted check the available clusters to verify the cluster is listed.

```bash
sacctmgr list clusters
```

## 🤝 Contributing

See [CONTRIBUTING](CONTRIBUTING.md) for more information.

## 📄 License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file for details.
