#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Add spack-users group
groupadd spack-users -g 4000

cat >> /etc/bashrc << 'EOF'
PATH=$PATH:/shared/software/bin
EOF
