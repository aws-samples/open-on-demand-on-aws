# Open OnDemand on AWS with Parallel Cluster

This reference architecture provides a set of templates for deploying [Open OnDemand (OOD)](https://openondemand.org/) with [AWS CloudFormation](https://aws.amazon.com/cloudformation/) and integration points for [AWS Parallel Cluster](https://aws.amazon.com/hpc/parallelcluster/).

The main branch is for Open OnDemand v 3.0.0 

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

This solution was tested with PCluster version 3.7.2. 


## Deployment 🚀
Download the cloudformation/openondemand.yml template, and use that to create a cloudformation stack in your AWS account and correct region.  

Once deployed, you should be able to navigate to the URL you set up as a CloudFormation parameter and log into your Open OnDemand portal. You can use the username `Admin` and retrieve the default password from Secrets Manager. The correct secret can be identified in the output of the Open OnDemand CloudFormation template via the entry with the key `ADAdministratorSecretArn`.

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

#### Optional - Enable pam_slurm_adopt module for Parallel Cluster compute nodes

The [pam_slurm_adopt](https://slurm.schedmd.com/pam_slurm_adopt.html) module can be enabled on the Compute nodes within ParallelCluster to prevent users from sshing into nodes that they do not have a running job on.  

In your Parallel Cluster config, you must set the following values:

1/ Enable the [PrologFlags: "contain"](https://slurm.schedmd.com/pam_slurm_adopt.html#important) should be in place to determine if any jobs have been allocated.  This can be set within the `Scheduling` section.

```
  SlurmSettings:  
    CustomSlurmSettings:
      - PrologFlags: "contain"
```

2/ [ExclusiveUser](https://slurm.schedmd.com/slurm.conf.html#OPT_ExclusiveUser) should be set to **YES** to cause nodes to be exclusively allocated to users.  This can be set within the `SlurmQueues` section.

```
  CustomSlurmSettings:
    ExclusiveUser: "YES"
```

3/ A new script [scripts/configure_pam_slurm_adopt.sh](scripts/configure_pam_slurm_adopt.sh) can be added to the `OnNodeConfigured` configuration within the `SlurmQueues` section to run a sequence of scripts.  
```
    CustomActions:
      OnNodeConfigured:
        Sequence:
        - Script: s3://$ClusterConfigBucket/pcluster_worker_node.sh
            Args:
            - Open OnDemand CloudFormation stack name
        - Script: s3://$ClusterConfigBucket/configure_pam_slurm_adopt.sh
```

### Integration Parallel Cluster Login Node

If [ParallelCluster Login Nodes](https://docs.aws.amazon.com/parallelcluster/latest/ug/login-nodes-v3.html) are being used a configuration script [configure_login_nodes.sh](scripts/configure_login_nodes.sh) can be used to configure the login node and enable it in Open OnDemand.

**Usage**
Replace the following values:
- `<OOD_STACK_NAME>` - name of the Open OnDemand stack name found in CloudFormation
- `<ClusterConfigBucket>` - 'ClusterConfigBucket' Output found in the Open OnDemand stack

Run the following script on the login node
```bash
S3_CONFIG_BUCKET=<ClusterConfigBucket> 
aws s3 cp s3://$S3_CONFIG_BUCKET/configure_login_nodes.sh .
chmod +x configure_login_nodes.sh
configure_login_nodes.sh <OOD_STACK_NAME>
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

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
