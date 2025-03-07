#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

yum -y -q install jq 
# Add spack-users group
groupadd spack-users -g 4000

## install remote desktop packages
## uncomment the following if you want to run interacctive remote desktop session in OOD
##
echo "Installing nmap-ncat" >> /var/log/configure_desktop.log
yum install nmap-ncat -y

cat > /etc/yum.repos.d/TurboVNC.repo <<  'EOF'
[TurboVNC]
name=TurboVNC official RPMs
baseurl=https://sourceforge.net/projects/turbovnc/files
gpgcheck=1
gpgkey=https://sourceforge.net/projects/turbovnc/files/VGL-GPG-KEY
       https://sourceforge.net/projects/turbovnc/files/VGL-GPG-KEY-1024
enabled=1
EOF

echo "Installing turbovnc" >> /var/log/configure_desktop.log
yum install turbovnc -y

amazon-linux-extras install python3.8
ln -sf /usr/bin/python3.8 /usr/bin/python3

echo "Installing pip packages" >> /var/log/configure_desktop.log
pip3 install --no-input websockify
pip3 install --no-input jupyter

echo "Installing mate-desktop1.x" >> /var/log/configure_desktop.log
amazon-linux-extras install mate-desktop1.x -y

echo "Updating bashrc" >> /var/log/configure_desktop.log
#
cat >> /etc/bashrc << 'EOF'
PATH=$PATH:/opt/TurboVNC/bin:/shared/software/bin
#this is to fix the dconf permission error
export XDG_RUNTIME_DIR="$HOME/.cache/dconf"
EOF

#
#wget https://download2.rstudio.org/server/centos7/x86_64/rstudio-server-rhel-2023.03.0-386-x86_64.rpm
# run this on compute node
#sudo yum install rstudio-server-rhel-2023.03.0-386-x86_64.rpm -y

#systemctl start rstudio-server
echo "DONE" >> /var/log/configure_desktop.log
