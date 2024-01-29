#!/bin/bash

set -euo pipefail

pushd /etc/pam.d &>/dev/null

for file in system-auth fingerprint-auth password-auth runuser-l; do
  echo "[-] Updating ${file}"
  sed -i -e '/pam_systemd.so/s/^/# /' ${file}
done

echo "[-] Updating password-auth"
sed -i -e '/pam_localuser.so/s/^/#/' password-auth

echo 'account required pam_slurm_adopt.so' >> /etc/pam.d/sshd
echo "[-] Finished!"
popd &>/dev/null
