#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

################################
# Install Slurm
################################

echo "[-] Installing prerequisites for slurm"
dnf install make rpm-build readline-devel \
    pam-devel perl-Switch perl-ExtUtils\* mariadb105-devel \
    cmake jansson-devel json-c-devel autoconf-archive \
    dbus-devel -y -q

cd /tmp

# install libjwt
LIBJWT_VERSION=1.17.0
echo "[-] installing libjwt ${LIBJWT_VERSION}"    
curl -Lo libjwt-${LIBJWT_VERSION}.tar.bz2 https://github.com/benmcollins/libjwt/releases/download/v${LIBJWT_VERSION}/libjwt-${LIBJWT_VERSION}.tar.bz2
tar -xf libjwt-${LIBJWT_VERSION}.tar.bz2
cd libjwt-${LIBJWT_VERSION}

autoreconf --force --install
./configure JANSSON_CFLAGS=-I/usr/include JANSSON_LIBS="-L/usr/lib -ljansson" --prefix=/usr
make
sudo make install

cd /tmp

wget https://download.schedmd.com/slurm/slurm-"${SLURM_VERSION}".tar.bz2
tar -xvjf slurm-"${SLURM_VERSION}".tar.bz2
cd slurm-"${SLURM_VERSION}"
echo "[-] configuring slurm"
./configure --prefix=/usr --sysconfdir=/etc/slurm --with-jwt=/usr --enable-pam;
make -j$(nproc)
make contrib
make install
make install-contrib

echo "[-] finishing installing slurm"
mkdir /etc/slurm

cp etc/cgroup.conf.example /etc/slurm/cgroup.conf
chown slurm -R /etc/slurm

# Copy any existing slurm configurations
aws s3 sync s3://${CLUSTER_CONFIG_BUCKET}/slurm /etc/slurm/ --exact-timestamps

# Add hostname -s to /etc/hosts
echo "127.0.0.1 $(hostname -s)" >> /etc/hosts

# If federation doesn't exist then create it
# EXISTING_FEDERATION=$(sacctmgr list federation Name=ood-cluster -n)
# if [ -z "$EXISTING_FEDERATION" ]; then
#     sacctmgr add federation ood-cluster -i
# fi
