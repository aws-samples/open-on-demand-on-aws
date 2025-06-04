#!/bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# Create an array of scripts to upload
scripts=(
    "pcluster_head_node.sh"
    "pcluster_worker_node.sh"
    "pcluster_worker_node_desktop.sh"
    "configure_login_nodes.sh"
    "configure_pam_slurm_adopt.sh"
    "configure_ood_for_pcs.sh"
    "configure_slurm.sh"
    "s3_script_runner.sh"
    "deploy_pcs.sh"
)

# Upload each script to S3
for script in "${scripts[@]}"; do
    echo "Uploading $script to s3://$CLUSTER_CONFIG_BUCKET/$script"
    aws s3 cp "$script" "s3://$CLUSTER_CONFIG_BUCKET/$script"
done

