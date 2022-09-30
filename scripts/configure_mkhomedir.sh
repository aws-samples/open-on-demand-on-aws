# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
authselect select sssd with-mkhomedir --force
systemctl enable sssd.service --now
systemctl enable oddjobd.service --now

authconfig --enablesssd --enablesssdauth --enablemkhomedir --updateall
sed -e '/PasswordAuthentication no/ s/^#*/#/' -i /etc/ssh/sshd_config
sed -i '/#PasswordAuthentication yes/s/^#//g' /etc/ssh/sshd_config

### Update PubkeyAuthentication to yes