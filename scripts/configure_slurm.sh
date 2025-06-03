#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# This script is called whenever a new slurm configuration (slurm.conf, slurmdbd.conf) 
# is uploaded to the CLUSTER_CONFIG_BUCKET (see config.json). It will update the
# slurm configuration and restart the slurmctld service.

set -euo pipefail

echo "[-] New slurm configuration(s) detected, restarting services..."
chown slurm:slurm -R /etc/slurm
sed -i "s/NodeName=.*$/NodeName=$(hostname -s)/" /etc/slurm/slurm.conf

echo "[-] Finished"
