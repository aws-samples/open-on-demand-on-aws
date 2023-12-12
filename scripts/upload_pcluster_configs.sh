#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
aws s3 cp pcluster_head_node.sh s3://$CLUSTER_CONFIG_BUCKET/pcluster_head_node.sh
aws s3 cp pcluster_worker_node.sh s3://$CLUSTER_CONFIG_BUCKET/pcluster_worker_node.sh
aws s3 cp pcluster_worker_node_desktop.sh s3://$CLUSTER_CONFIG_BUCKET/pcluster_worker_node_desktop.sh
aws s3 cp configure_login_nodes.sh s3://$CLUSTER_CONFIG_BUCKET/configure_login_nodes.sh
aws s3 cp configure_pam_slurm_adopt.sh s3://$CLUSTER_CONFIG_BUCKET/configure_pam_slurm_adopt.sh
