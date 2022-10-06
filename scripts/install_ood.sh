# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
dnf module enable ruby:2.7 -y
dnf module enable nodejs:12 -y

yum install https://yum.osc.edu/ondemand/2.0/ondemand-release-web-2.0-1.noarch.rpm -y -q

yum install openssl ondemand ondemand-selinux ondemand-dex krb5-workstation samba-common-tools amazon-efs-utils -y -q

export AD_SECRET=$(aws secretsmanager --region $AWS_REGION get-secret-value --secret-id $AD_SECRET_ID --query SecretString --output text)
export AD_PASSWORD=$(aws secretsmanager --region $AWS_REGION get-secret-value --secret-id $AD_PASSWORD --query SecretString --output text)
export ALB_NAME=${!ALB_DNS_NAME,,} # Need to make it lower case as apache is case sensitive

sed -i "s/#servername: null/servername: $WEBSITE_DOMAIN/" /etc/ood/config/ood_portal.yml

cat << EOF >> /etc/ood/config/ood_portal.yml
ssl:
  - 'SSLCertificateFile "/etc/ssl/private/cert.crt"'
  - 'SSLCertificateKeyFile "/etc/ssl/private/private_key.key"'
EOF

cat << EOF >> /etc/ood/config/ood_portal.yml
dex:
    client_id: $WEBSITE_DOMAIN
    ssl: true
    connectors:
        - type: ldap
          id: ldap
          name: LDAP
          config:
            host: $LDAP_NLB
            insecureSkipVerify: false
            insecureNoSSL: true
            bindDN: cn=Administrator,CN=Users,dc=$DOMAIN_NAME,dc=$TOP_LEVEL_DOMAIN
            bindPW: $AD_PASSWORD
            userSearch:
              baseDN: dc=$DOMAIN_NAME,dc=$TOP_LEVEL_DOMAIN
              filter: "(objectClass=user)"
              username: name
              idAttr: name
              emailAttr: name
              nameAttr: name
              preferredUsernameAttr: name
EOF

# # Tells PUN to look for home directories in EFS
cat << EOF >> /etc/ood/config/nginx_stage.yml
user_home_dir: '/shared/home/%{user}'
EOF


# Set up directories for clusters and interactive desktops
mkdir -p /etc/ood/config/clusters.d
mkdir -p /etc/ood/config/apps/bc_desktop


# Setup OOD add user; will add local user for AD user if doesn't exist
touch /var/log/add_user.log
chown apache /var/log/add_user.log
touch /etc/ood/add_user.sh
touch /shared/userlistfile
mkdir -p /shared/home

# Script that we want to use when adding user
cat << EOF >> /etc/ood/add_user.sh
if ! id "\$1-local" &>/dev/null; then
  echo "Adding user \$1-local" >> /var/log/add_user.log
  sudo adduser \$1-local --home /shared/home/\$1 >> /var/log/add_user.log
  usermod -a -G spack-users \$1-local
  mkdir -p /shared/home/\$1 >> /var/log/add_user.log
  chown \$1-local /shared/home/\$1 >> /var/log/add_user.log
  echo "\$1 \$(id -u \$1-local)" >> /shared/userlistfile
  sudo su \$1-local -c 'ssh-keygen -t rsa -f ~/.ssh/id_rsa -q -P ""'
  sudo su \$1-local -c 'cat ~/.ssh/id_rsa.pub > ~/.ssh/authorized_keys'
  chmod 600 /shared/home/\$1/.ssh/*
fi
echo \$1-local
EOF


echo "user_map_cmd: '/etc/ood/add_user.sh'" >> /etc/ood/config/ood_portal.yml

# Creates a script where we can re-create local users on PCluster nodes.
# Since OOD uses local users, need those same local users with same UID on PCluster nodes
cat << EOF >> /shared/copy_users.sh
while read USERNAME USERID
do
    # -u to set UID to match what is set on the head node
    if [ \$(grep -c '^\$USERNAME-local:' /etc/passwd) -eq 0 ]; then
        useradd -u \$USERID \$USERNAME-local -d /shared/home/\$USERNAME
        usermod -a -G spack-users \$USERNAME-local
    fi
done < "/shared/userlistfile"
EOF

chmod +x /etc/ood/add_user.sh
chmod +x /shared/copy_users.sh
chmod o+w /shared/userlistfile

/opt/ood/ood-portal-generator/sbin/update_ood_portal
systemctl enable httpd
systemctl enable ondemand-dex

# install bin overrides so sbatch executes on remote node
pip3 install sh pyyaml
#create sbatch log
touch /var/log/sbatch.log
chmod 666 /var/log/sbatch.log

# Create this bin overrides script on the box: https://osc.github.io/ood-documentation/latest/installation/resource-manager/bin-override-example.html
cat << EOF >> /etc/ood/config/bin_overrides.py
#!/bin/python3
from getpass import getuser
from select import select
from sh import ssh, ErrorReturnCode
import logging
import os
import re
import sys
import yaml

'''
An example of a `bin_overrides` replacing Slurm `sbatch` for use with Open OnDemand.
Executes sbatch on the target cluster vs OOD node to get around painful experiences with sbatch + EFA.

Requirements:

- $USER must be able to SSH from web node to submit node without using a password
'''
logging.basicConfig(filename='/var/log/sbatch.log', level=logging.INFO)

USER = os.environ['USER']
LOCAL_USER=USER+"-local"


def run_remote_sbatch(script,host_name, *argv):
  """
  @brief      SSH and submit the job from the submission node

  @param      script (str)  The script
  @parma      host_name (str) The hostname of the head node on which to execute the script
  @param      argv (list<str>)    The argument vector for sbatch

  @return     output (str) The merged stdout/stderr of the remote sbatch call
  """

  output = None

  try:
    result = ssh(
      '@'.join([LOCAL_USER, host_name]),
      '-oBatchMode=yes',  # ensure that SSH does not hang waiting for a password that will never be sent
      '-oStrictHostKeyChecking=no',
      '/opt/slurm/bin/sbatch',  # the real sbatch on the remote
      *argv,  # any arguments that sbatch should get
      _in=script,  # redirect the script's contents into stdin
      _err_to_out=True  # merge stdout and stderr
    )

    output = result.stdout.decode('utf-8')
    logging.info(output)
  except ErrorReturnCode as e:
    output = e.stdout.decode('utf-8')
    logging.error(output)
    print(output)
    sys.exit(e.exit_code)

  return output

def load_script():
  """
  @brief      Loads a script from stdin.

  With OOD and Slurm the user's script is read from disk and passed to sbatch via stdin
  https://github.com/OSC/ood_core/blob/5b4d93636e0968be920cf409252292d674cc951d/lib/ood_core/job/adapters/slurm.rb#L138-L148

  @return     script (str) The script content
  """
  # Do not hang waiting for stdin that is not coming
  if not select([sys.stdin], [], [], 0.0)[0]:
    logging.error('No script available on stdin!')
    sys.exit(1)

  return sys.stdin.read()

def get_cluster_host(cluster_name):
  with open(f"/etc/ood/config/clusters.d/{cluster_name}.yml", "r") as stream:
    try:
      config_file=yaml.safe_load(stream)
    except yaml.YAMLError as e:
      logging.error(e)
  return config_file["v2"]["login"]["host"]

def main():
  """
  @brief SSHs from web node to submit node and executes the remote sbatch.
  """
  host_name=get_cluster_host(sys.argv[-1])
  output = run_remote_sbatch(
    load_script(),
    host_name,
    sys.argv[1:]
  )

  print(output)

if __name__ == '__main__':
  main()
EOF

chmod +x /etc/ood/config/bin_overrides.py
#Edit sudoers to allow apache to add users
echo "apache  ALL=/sbin/adduser" >> /etc/sudoers
echo "apache  ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
reboot