# Open OnDemand on AWS with Parallel Cluster

This reference architecture provides a set of templates for deploying [Open OnDemand (OOD)](https://openondemand.org/) with [AWS CloudFormation](https://aws.amazon.com/cloudformation/) and integration points for [AWS Parallel Cluster](https://aws.amazon.com/hpc/parallelcluster/).

The main branch is for Open OnDemand v 4.0.1

## Architecture

![architecture](images/architecture.png)

The primary components of the solution are:

1. Application load balancer as the entry point to your OOD portal.
1. An Auto Scaling Group for the OOD Portal.
1. A Microsoft ManagedAD Directory
1. A Network Load Balancer (NLB) to provide a single point of connectivity to Microsoft ManagedAD
1. An Elastic File System (EFS) share for user home directories
1. An Aurora MySQL database to store Slurm Accounting data
1. Automation via Event Bridge to automatically register and deregister Parallel Cluster HPC Clusters with OOD

## Prerequisites

This solution was tested with AWS ParallelCluster version [3.11.0](https://github.com/aws/aws-parallelcluster/releases/tag/v3.11.0)

## Deployment 🚀

### All-in-one Deployment

All in one deployment including **infrastructure** and **Open OnDemand**

1. Run [deploy-assets.sh](deploy-assets.sh) to deploy the CloudFormation assets to an S3 bucket in the respective AWS account
2. Deploy all-in-one stack [ood_full.yml](assets/cloudformation/ood_full.yml)

**Note**: `DeploymentAssetBucketName` is the output from step 1 (deploy assets)

### Individual Component Deployment

**Deploy Stacks individually:**

1. Deploy Infrastructure (*Networking, and Managed Active Directory*): [infra.yml](assets/cloudformation/infra.yml)
2. Deploy Slurm Accounting Database: [slurm_accounting_db.yml](assets/cloudformation/slurm_accounting_db.yml)
3. Deploy Open OnDemand: [ood.yml](assets/cloudformation/ood.yml)

### Post Deployment Steps

Once deployed, you should be able to navigate to the URL you set up as a CloudFormation parameter and log into your Open OnDemand portal. You can use the username `Admin` and retrieve the default password from Secrets Manager. The correct secret can be identified in the output of the Open OnDemand CloudFormation template via the entry with the key `ADAdministratorSecretArn`.

### Deploying an integrated Parallel Cluster HPC Cluster

The OOD solution is built so that an [AWS ParallelCluster](https://docs.aws.amazon.com/parallelcluster/latest/ug/what-is-aws-parallelcluster.html) HPC Cluster can be created and automatically registered with the portal.

In your Parallel Cluster config, you must set the following values:

1. **HeadNode**:
    1. SubnetId: `PrivateSubnets` from OOD Stack Output
    1. AdditionalScurityGroups: `HeadNodeSecurityGroup` from CloudFormation Outputs
    1. AdditionalIAMPolicies: `HeadNodeIAMPolicyArn` from CloudFormation Outputs
    1. OnNodeConfigured
        1. Script: CloudFormation Output for the `ClusterConfigBucket`; in the format `s3://$ClusterConfigBucket/pcluster_head_node.sh`
        1. Args: Open OnDemand CloudFormation stack name
1. **SlurmQueues**:
    1. SubnetId: `PrivateSubnets` from OOD Stack Output
    1. AdditionalScurityGroups: `ComputeNodeSecurityGroup` from CloudFormation Outputs
    1. AdditionalIAMPolicies: `ComputeNodeIAMPolicyArn` from CloudFormation Outputs
    1. OnNodeConfigured
        1. Script: CloudFormation Output for the `ClusterConfigBucket`; in the format `s3://$ClusterConfigBucket/pcluster_worker_node.sh`
        . Args: Open OnDemand CloudFormation stack name
1. **LoginNode**:
    1. OnNodeConfigured
        1. Script: CloudFormation Output for the `ClusterConfigBucket`; in the format `s3://$ClusterConfigBucket/configure_login_nodes.sh`
        1. Args: Open OnDemand CloudFormation stack name

---

To make this easier a sample `pcluster` configuration can be created using [scripts/create_sample_pcluster_config.sh](scripts/create_sample_pcluster_config.sh)

```
Usage: ./scripts/create_sample_pcluster_config.sh <stack-name> [region] [domain1] [domain2]
  stack-name: The name of the stack you deployed
  region: The region of the stack you deployed
  domain1: The first domain name to use for the cluster
  domain2: The second domain name to use for the cluster
```

#### Optional - Enable pam_slurm_adopt module for Parallel Cluster compute nodes

The [pam_slurm_adopt](https://slurm.schedmd.com/pam_slurm_adopt.html) module can be enabled on Compute nodes in ParallelCluster to prevent users from ssh'ing to nodes they do not have a job running.

In your Parallel Cluster config, update the following configuration(s):

1/ Check if any steps have been launched.

Add the **CustomSlurmSetting** `PrologFlags: "contain"` in the [Scheduling](https://docs.aws.amazon.com/parallelcluster/latest/ug/Scheduling-v3.html) section.  Refer to [slurm configuration](https://slurm.schedmd.com/pam_slurm_adopt.html#important) documentation for more details on this slurm setting.

*example*
```
  SlurmSettings:  
    CustomSlurmSettings:
      - PrologFlags: "contain"
```

2/ Ensure compute nodes are exclusively allocated to users.  

Add the **CustomSlurmSetting** `ExclusiveUser: "YES"` in the [SlurmQueues](https://docs.aws.amazon.com/parallelcluster/latest/ug/Scheduling-v3.html#Scheduling-v3-SlurmQueues) section.  Refer to [slurm partition configuration](https://slurm.schedmd.com/slurm.conf.html#OPT_ExclusiveUser) for more details.

*example*
```
  CustomSlurmSettings:
    ExclusiveUser: "YES"
```

3/ Add [configure_pam_slurm_adopt.sh](scripts/configure_pam_slurm_adopt.sh) to **OnNodeConfigured** in the [CustomActions](https://docs.aws.amazon.com/parallelcluster/latest/ug/Scheduling-v3.html#Scheduling-v3-SlurmQueues-CustomActions) section.  

*example*
```
    CustomActions:
      OnNodeConfigured:
        Sequence:
        - Script: s3://$ClusterConfigBucket/pcluster_worker_node.sh
            Args:
            - Open OnDemand CloudFormation stack name
        - Script: s3://$ClusterConfigBucket/configure_pam_slurm_adopt.sh
```

### Enabling Interactive Desktops

You can enable interactive clusters on the Portal server by following the directions [here](https://osc.github.io/ood-documentation/latest/enable-desktops/add-cluster.html).

In addition to the above steps, you must update `/etc/resolv.conf` on the Portal instance to include the Parallel Cluster Domain (`ClusterName.pcluster`) in the search configuration. `resolv.conf` will look similar to the example below. The cluster name, in this case was `democluster`.

Example resolv.confg:
```
# Generated by NetworkManager
search ec2.internal democluster.pcluster
nameserver 10.0.0.2
```

This requires you to have a compute queue with `pcluster_worker_node_desktop.sh` as your `OnNodeConfigured` script.

## Slurm Configuration Management

Slurm configuration can be maintained outside of the Open OnDemand deployment.  

The `ClusterConfigBucket` S3 bucket (_found in CloudFormation Outputs_) can contain slurm configuration(s) inside the `/slurm` prefix.  Any files in `/etc/slurm` directory can be added to this prefix and will be automatically deployed to the Open OnDemand server by way of an EventBridge rule.  

The following configurations are stored by default:

- [slurm.conf](https://slurm.schedmd.com/slurm.conf.html)
- [slurmdbd.conf](https://slurm.schedmd.com/slurmdbd.conf.html)

### How to update slurm configuration

To update the slurm configuration on the Open OnDemand server copy any configuration file(s) to the `ClusterConfigBucket` s3 bucket.  

e.g. Pushing a `slurm.conf` configuration update.  
**Note:** Replace `OOD_STACK` with the name of your OOD CloudFormation stack.

```bash
OOD_STACK="<insert ood stack name here>"
CLUSTER_CONFIG_BUCKET=$(echo $OOD_STACK | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="ClusterConfigBucket") | .OutputValue')
aws s3 cp slurm.conf s3://$CLUSTER_CONFIG_BUCKET/slurm/
```

## RHEL9 support

RHEL9 has been added as another deployment option.  To deploy use the [rhel9-support](https://github.com/aws-samples/open-on-demand-on-aws/tree/rhel9-support) branch for deployment.

## Troubleshooting

### Issue submitting jobs after adding a ParallelCluster

There can be errors submitting jobs after integrating OOD w/ParalleCluster due to slurm registering the cluster.  Review the logs found in `/var/log/sbatch.log` and check if there are errors related to available clusters.

*sample log entry*
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

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
