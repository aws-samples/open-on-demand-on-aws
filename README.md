# Open OnDemand on AWS with Parallel Cluster

This reference architecture provides a set of templates for deploying [Open OnDemand (OOD)](https://openondemand.org/) with [AWS CloudFormation](https://aws.amazon.com/cloudformation/) and integration points for [AWS Parallel Cluster](https://aws.amazon.com/hpc/parallelcluster/).

## Architecture

![architecture](images/architecture.png)

The primary components of the solution are:

1. Application load balancer as the entry point to your OOD portal.
1. An Auto Scaling Group for the OOD Portal.
1. A SimpleAD LDAP Directory
1. A Network Load Balancer (NLB) to provide a single point of connectivity to SimpleAD
1. An Elastic File System (EFS) share for user home directories
1. An Aurora MySQL database to store Slurm Accounting data
1. Automation via Event Bridge to automatically register and deregister Parallel Cluster HPC Clusters with OOD

## Prerequisites

1. Route53 domain for your OOD portal

## Deployment 🚀

1. Launch the stack in your AWS account by clicking on one of the below regions:


| Region           | Launch                                                                                                                                                                                                                                                                                                                           |
|------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Ohio (us-east-2) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/us-east-2.svg)](https://us-east-2.console.aws.amazon.com/cloudformation/home?region=us-east-2#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| N. Virginia (us-east-1) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/us-east-1.svg)](https://us-east-1.console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| Ireland (eu-west-1) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/eu-west-1.svg)](https://eu-west-1.console.aws.amazon.com/cloudformation/home?region=eu-west-1#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| Frankfurt (eu-central-1) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/eu-central-1.svg)](https://eu-central-1.console.aws.amazon.com/cloudformation/home?region=eu-central-1#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |

<details>
    <summary>More Regions (Click to expand)</summary>

| Region           | Launch                                                                                                                                                                                                                                                                                                                           |
|------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Oregon (us-west-2) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/us-west-2.svg)](https://us-west-2.console.aws.amazon.com/cloudformation/home?region=us-west-2#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| California (us-west-1) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/us-west-1.svg)](https://us-west-1.console.aws.amazon.com/cloudformation/home?region=us-west-1#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| London (eu-west-2) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/eu-west-2.svg)](https://eu-west-2.console.aws.amazon.com/cloudformation/home?region=eu-west-2#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| Paris (eu-west-3) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/eu-west-3.svg)](https://eu-west-3.console.aws.amazon.com/cloudformation/home?region=eu-west-3#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| Stockholm (eu-north-1) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/eu-north-1.svg)](https://eu-north-1.console.aws.amazon.com/cloudformation/home?region=eu-north-1#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| Middle East (me-south-1) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/me-south-1.svg)](https://me-south-1.console.aws.amazon.com/cloudformation/home?region=me-south-1#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| South America (sa-east-1) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/sa-east-1.svg)](https://sa-east-1.console.aws.amazon.com/cloudformation/home?region=sa-east-1#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| Canada (ca-central-1) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/ca-central-1.svg)](https://ca-central-1.console.aws.amazon.com/cloudformation/home?region=ca-central-1#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| Tokyo (ap-northeast-1) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/ap-northeast-1.svg)](https://ap-northeast-1.console.aws.amazon.com/cloudformation/home?region=ap-northeast-1#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| Seoul (ap-northeast-2) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/ap-northeast-2.svg)](https://ap-northeast-2.console.aws.amazon.com/cloudformation/home?region=ap-northeast-2#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| Mumbai (ap-south-1) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/ap-south-1.svg)](https://ap-south-1.console.aws.amazon.com/cloudformation/home?region=ap-south-1#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| Singapore (ap-southeast-1) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/ap-southeast-1.svg)](https://ap-southeast-1.console.aws.amazon.com/cloudformation/home?region=ap-southeast-1#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
| Sydney (ap-southeast-2) | [![Launch](https://samdengler.github.io/cloudformation-launch-stack-button-svg/images/ap-southeast-2.svg)](https://ap-southeast-2.console.aws.amazon.com/cloudformation/home?region=ap-southeast-2#/stacks/create/review?stackName=open-ondemand&templateURL=https://aws-hpc-workshops.s3.amazonaws.com/openondemand.yml) |
</details>

Once deployed, you should be able to navigate to the URL you set up as a CloudFormation parameter and log into your Open OnDemand portal. You can use the username `Administrator` and retrieve the default password from Secrets Manager. The correct secret can be identified in the output of the Open OnDemand CloudFormation template via the entry with the key `ADAdministratorSecretArn`.

### Deploying an integrated Parallel Cluster HPC Cluster

The OOD solution is built so that a Parallel Cluster HPC Cluster can be created and automatically registered with the portal.

In your Parallel Cluster config, you must set the following values:

1. HeadNode:
    1. SubnetId: PrivateSubnet1 from OOD Stack Output
    1. AdditionalScurityGroups: HeadNodeSecurityGroup from CloudFormation Outputs
    1. AdditionalIAMPolicies: HeadNodeIAMPolicyArn from CloudFormation Outputs
    1. OnNodeConfigured
        1. Script: CloudFormation Output for the ClusterConfigBucket; in the format `s3://$ClusterConfigBucket/pcluster_head_node.sh`
        1. Args: Open OnDemand CloudFormation stack name
1. SlurmQueues:
    1. SubnetId: PrivateSubnet1 from OOD Stack Output
    1. AdditionalScurityGroups: ComputeNodeSecurityGroup from CloudFormation Outputs
    1. AdditionalIAMPolicies: ComputeNodeIAMPolicyArn from CloudFormation Outputs
    1. OnNodeConfigured
        1. Script: CloudFormation Output for the ClusterConfigBucket; in the format `s3://$ClusterConfigBucket/pcluster_worker_node.sh`
        1. Args: Open OnDemand CloudFormation stack name

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
