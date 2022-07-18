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
echo "Adding user \$1" >> /var/log/add_user.log
sudo adduser \$1 --home /shared/home/\$1 >> /var/log/add_user.log
mkdir -p /shared/home/\$1 >> /var/log/add_user.log
chown \$1 /shared/home/\$1 >> /var/log/add_user.log
echo "\$1 \$(id -u \$1)" >> /shared/userlistfile

echo \$1
EOF

echo "user_map_cmd: '/etc/ood/add_user.sh'" >> /etc/ood/config/ood_portal.yml

# Creates a script where we can re-create local users on PCluster nodes.
# Since OOD uses local users, need those same local users with same UID on PCluster nodes
cat << EOF >> /shared/copy_users.sh
while read USERNAME USERID
do
    # -M do not create home since head node is exporting /shared/home via NFS
    # -u to set UID to match what is set on the head node
    if [ \$(grep -c '^$USERNAME:' /etc/passwd) -eq 0 ]; then
        useradd -M -u \$USERID \$USERNAME
    fi
done < "/shared/userlistfile"
EOF

chmod +x /etc/ood/add_user.sh
chmod +x /shared/copy_users.sh

/opt/ood/ood-portal-generator/sbin/update_ood_portal
systemctl enable httpd
systemctl enable ondemand-dex

#Edit sudoers to allow apache to add users
echo "apache  ALL=/sbin/adduser" >> /etc/sudoers
reboot