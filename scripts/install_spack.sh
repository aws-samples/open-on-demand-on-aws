#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
cd /shared
mkdir spack
chgrp spack-users /shared/spack
chmod g+swrx /shared/spack

git clone -c feature.manyFiles=true --depth=2 https://github.com/spack/spack.git
dnf swap gnupg2-minimal gnupg2-full -y -q
. /shared/spack/share/spack/setup-env.sh

spack mirror add binary_mirror https://binaries.spack.io/develop
spack buildcache keys --install --trust

chmod -R g+wrx /shared/spack
chown -R :spack-users /shared/spack

cat << EOF > $SPACK_ROOT/etc/spack/packages.yaml
packages:
    intel-mpi:
        externals:
        - spec: intel-mpi@2020.4.0
          prefix: /opt/intel/mpi/2021.4.0/
        buildable: False
    libfabric:
        variants: fabrics=efa,tcp,udp,sockets,verbs,shm,mrail,rxd,rxm
        externals:
        - spec: libfabric@1.13.2 fabrics=efa,tcp,udp,sockets,verbs,shm,mrail,rxd,rxm
          prefix: /opt/amazon/efa
        buildable: False
    openmpi:
        variants: fabrics=ofi +legacylaunchers schedulers=slurm ^libfabric
        externals:
        - spec: openmpi@4.1.1 %gcc@7.3.1
          prefix: /opt/amazon/openmpi
    pmix:
        externals:
          - spec: pmix@3.2.3 ~pmi_backwards_compatibility
            prefix: /opt/pmix
    slurm:
        variants: +pmix sysconfdir=/opt/slurm/etc
        externals:
        - spec: slurm@21.08.8-2 +pmix sysconfdir=/opt/slurm/etc
          prefix: /opt/slurm
        buildable: False
EOF

# Improve usability of spack for Tcl Modules
spack config --scope site add "modules:default:tcl:all:autoload: direct"
spack config --scope site add "modules:default:tcl:verbose: True"
spack config --scope site add "modules:default:tcl:hash_length: 6"
spack config --scope site add "modules:default:tcl:projections:all:'{name}/{version}-{compiler.name}-{compiler.version}'"
spack config --scope site add "modules:default:tcl:all:conflict:['{name}']"
spack config --scope site add "modules:default:tcl:all:suffixes:^cuda:cuda"
spack config --scope site add "modules:default:tcl:all:environment:set:{name}_ROOT:'{prefix}'"
spack config --scope site add "modules:default:tcl:openmpi:environment:set:SLURM_MPI_TYPE:'pmix'"
spack config --scope site add "modules:default:tcl:openmpi:environment:set:OMPI_MCA_btl_tcp_if_exclude:'lo,docker0,virbr0'"
spack config --scope site add "modules:default:tcl:intel-oneapi-mpi:environment:set:SLURM_MPI_TYPE:'pmi2'"
spack config --scope site add "modules:default:tcl:mpich:environment:set:SLURM_MPI_TYPE:'pmi2'"

echo "[+] Finished!"
