#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Desktop-node bootstrap: installs NICE DCV (Amazon DCV) + a desktop environment
# so Open OnDemand can deliver interactive Linux desktops through its reverse
# proxy (/rnode/...).
#
# Single source of truth for both cluster paths:
#   - AWS ParallelCluster: run via CustomActions.OnNodeConfigured (from S3)
#   - AWS PCS: fetched + run from the desktop launch-template UserData (from S3)
#
# OS-agnostic: detects the running distro + architecture and selects the matching
# DCV package family, so it works across the OSes ParallelCluster supports
# (alinux2, alinux2023, rhel8/9, rocky8/9, ubuntu 20.04/22.04/24.04; x86_64 +
# aarch64). Only Amazon Linux 2023 / x86_64 has been validated end-to-end; the
# other combinations follow the DCV Linux install guide and should be verified
# before production use.
# Refs: https://docs.aws.amazon.com/dcv/latest/adminguide/setting-up-installing-linux-server.html
#       https://docs.aws.amazon.com/parallelcluster/latest/ug/Image-v3.html#yaml-Image-Os

set -euo pipefail
LOG=/var/log/configure_desktop.log
exec >> "$LOG" 2>&1
echo "[-] $(date) starting DCV desktop bootstrap"

DCV_BASE=https://d1uj6qtbmh3dt5.cloudfront.net

# --- Detect OS + architecture and map to the DCV package token / family ---
# shellcheck disable=SC1091
. /etc/os-release
ARCH=$(uname -m)                       # x86_64 | aarch64
os_key="${ID}${VERSION_ID%%.*}"        # e.g. amzn2023, rhel9, rocky8, ubuntu22
dcv_os=""                              # token used in the DCV tarball / dir name
family=""                              # rpm | deb
case "$os_key" in
  amzn2023)                          dcv_os="amzn2023";   family="rpm" ;;
  amzn2)                             dcv_os="amzn2";      family="rpm" ;;
  rhel8|rocky8|centos8|almalinux8)   dcv_os="el8";        family="rpm" ;;
  rhel9|rocky9|centos9|almalinux9)   dcv_os="el9";        family="rpm" ;;
  ubuntu20)                          dcv_os="ubuntu2004"; family="deb" ;;
  ubuntu22)                          dcv_os="ubuntu2204"; family="deb" ;;
  ubuntu24)                          dcv_os="ubuntu2404"; family="deb" ;;
  *) echo "[!] Unsupported OS '${ID} ${VERSION_ID}' for DCV auto-install" >&2; exit 1 ;;
esac
echo "[-] detected os_key=${os_key} dcv_os=${dcv_os} family=${family} arch=${ARCH}"

# --- Base packages + desktop ENVIRONMENT + DCV package install (per family) ---
# nice-xdcv (installed below) is the virtual X server, not a desktop environment;
# both layers are required and are the supported DCV combo.
install_base_and_desktop() {
  case "$family" in
    rpm)
      dnf install -y jq nmap-ncat glx-utils mesa-dri-drivers mesa-libGL
      case "$dcv_os" in
        amzn2023)  dnf groupinstall -y "Desktop" ;;
        amzn2)     amazon-linux-extras install -y mate-desktop1.x ;;
        el8|el9)   dnf groupinstall -y "Server with GUI" ;;
      esac
      ;;
    deb)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y jq ncat mesa-utils libgl1-mesa-dri
      apt-get install -y ubuntu-desktop-minimal || apt-get install -y ubuntu-desktop
      ;;
  esac
}

import_dcv_key() {
  case "$family" in
    rpm) rpm --import "${DCV_BASE}/NICE-GPG-KEY" ;;
    deb) curl -fsSL -o /tmp/NICE-GPG-KEY "${DCV_BASE}/NICE-GPG-KEY"; gpg --import /tmp/NICE-GPG-KEY || true ;;
  esac
}

install_dcv_packages() {
  local dir="$1"
  case "$family" in
    rpm)
      dnf install -y \
        "$dir"/nice-dcv-server-*.rpm \
        "$dir"/nice-dcv-web-viewer-*.rpm \
        "$dir"/nice-xdcv-*.rpm \
        "$dir"/nice-dcv-simple-external-authenticator-*.rpm
      ;;
    deb)
      export DEBIAN_FRONTEND=noninteractive
      apt-get install -y \
        "$dir"/nice-dcv-server_*.deb \
        "$dir"/nice-dcv-web-viewer_*.deb \
        "$dir"/nice-xdcv_*.deb \
        "$dir"/nice-dcv-simple-external-authenticator_*.deb
      usermod -aG video dcv || true   # required for the dcv user on Ubuntu (per DCV docs)
      ;;
  esac
}

echo "[-] installing base packages + desktop environment"
install_base_and_desktop

# spack-users group to match the shared software stack mount.
groupadd spack-users -g 4000 || true

echo "[-] installing NICE DCV (server + web viewer + xdcv + simple external authenticator)"
import_dcv_key
DCV_TGZ="/tmp/nice-dcv-${dcv_os}-${ARCH}.tgz"
curl -fsSL -o "$DCV_TGZ" "${DCV_BASE}/nice-dcv-${dcv_os}-${ARCH}.tgz"
tar -xzf "$DCV_TGZ" -C /tmp
DCV_DIR=$(find /tmp -maxdepth 1 -type d -name "nice-dcv-*-${dcv_os}-${ARCH}" | head -1)
if [ -z "$DCV_DIR" ]; then echo "[!] extracted DCV directory not found" >&2; exit 1; fi
install_dcv_packages "$DCV_DIR"

echo "[-] configuring DCV for the OOD reverse proxy"
# Set a key inside a dcv.conf section, replacing any active setting (crudini is
# not packaged everywhere, so use sed): drop an existing active line, then insert
# the key immediately under its [section] header.
set_dcv_conf() {
  local section="$1" key="$2" value="$3" file=/etc/dcv/dcv.conf
  sed -i "/^${key}[[:space:]]*=/d" "$file"
  sed -i "/^\[${section}\]/a ${key}=${value}" "$file"
}
# web-url-path stays "/" : OOD's node_proxy strips the /rnode/<host>/<port> prefix
# before forwarding, so DCV serves at root (its client emits relative asset URLs).
set_dcv_conf connectivity web-url-path '"/"'
# Point DCV at the local simple external authenticator so the per-session tokens
# the dcv.rb batch-connect template issues (dcvsimpleextauth add-user) validate.
set_dcv_conf security auth-token-verifier '"https://127.0.0.1:8444"'

echo "[-] enabling DCV services"
systemctl enable --now dcvserver dcvsimpleextauth

# Virtual sessions use Xdcv as the X server; no Xorg/XDummy/GDM needed. Keep the
# node at multi-user.target (avoids GDM/Wayland); do NOT switch to graphical.target.
echo "[-] setting multi-user.target"
systemctl set-default multi-user.target

BASHRC=/etc/bashrc; [ "$family" = "deb" ] && BASHRC=/etc/bash.bashrc
echo "[-] updating ${BASHRC}"
cat >> "$BASHRC" << 'EOF'
PATH=$PATH:/shared/software/bin
# fix dconf permission error under virtual DCV sessions
export XDG_RUNTIME_DIR="$HOME/.cache/dconf"
EOF

echo "[-] $(date) DONE"
