#!/bin/bash

# This script generates SSH configuration files for OOD clusters.
# It iterates over the cluster configurations and generates a SSH configuration
# file for each cluster. 


set -euo pipefail

# Iterate over the cluster configurations and generate a SSH configuration
for cluster_config in $(ls -1 /etc/ood/config/clusters.d/*.yml); do
  cluster_name=$(basename $cluster_config .yml)

  # Get the cluster host from the configuration file
  cluster_host=$(yq -r '.v2.login.host' $cluster_config)
  
  # Generate SSH configuration
  echo "[-] Generating SSH configuration for $cluster_name..."
  cat << EOF > /etc/ssh/ssh_config.d/ood_${cluster_name}.conf
Host ${cluster_host}
  LogLevel Error
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
  PasswordAuthentication no
EOF
done

echo "[+] SSH configuration generated successfully."

# Add open ondemand desktop configuration
# This configuration assumes there will be slurm queue called 'desktop'
cat << EOF > /etc/ood/config/apps/bc_desktop/${cluster_name}.yml
---
title: "Linux Desktop on ${cluster_name}"
cluster: "${cluster_name}"
attributes:
  desktop: "mate"
  bc_queue: "desktop"
  account: "enduser-research-account"
EOF
