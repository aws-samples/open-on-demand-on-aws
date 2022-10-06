# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
yum install git -y
cd /shared
mkdir spack
chgrp spack-users /shared/spack
chmod g+swrx /shared/spack
git clone https://github.com/spack/spack
