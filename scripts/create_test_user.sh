# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
yum install openldap* -y -q

LDAP_NLB=ood-thi-NLB-T3I1NA9P9NET-87987e997ac8df06.elb.us-east-1.amazonaws.com
LDAP_ADMIN_PASS=".T^{x1w1cRsL"

cat << EOF >> new_user.ldif
dn: cn=polchr1,CN=Users,dc=hpclab,dc=local
objectClass: user
uid: polchr1
name: polchr1
cn: polchr1
sn: polchr1
mail: polchr1@amazon.com
userPassword: pass1word!
objectClass: posixAccount
sAMAccountName: polchr1
homeDirectory: /shared/home/polchr1
EOF


ldapadd -h $LDAP_NLB -x -D Administrator@hpclab.local -w "$LDAP_ADMIN_PASS" -f new_user.ldif


ldapsearch -x -LLL -h $LDAP_NLB -D Administrator@hpclab.local -w "$LDAP_ADMIN_PASS"  -b "cn=polchr,cn=Users,dc=hpclab,dc=local"


aws ds reset-user-password --directory-id d-90675bf63d --user-name polchr --new-password pass1word!

ldappasswd -H  ldap://$LDAP_NLB -x -D Administrator@hpclab.local -w "$LDAP_ADMIN_PASS" -S "cn=polchr,cn=Users,dc=hpclab,dc=local"

ldapmodify -H ldap://$LDAP_NLB -D Administrator@hpclab.local -w "$LDAP_ADMIN_PASS" -f new_user.ldif



cat << EOF >> new_user.ldif
dn: cn=polchr3,CN=Users,dc=hpclab,dc=local
objectClass: user
uid: polchr3
name: polchr3
cn: polchr3
sn: polchr3
mail: polchr+2@amazon.com
userPassword: pass1word!
objectClass: posixAccount
sAMAccountName: polchr3
homeDirectory: /shared/home/polchr3
EOF


ldapadd -h $LDAP_NLB -x -D Administrator@hpclab.local -w "$LDAP_ADMIN_PASS" -f new_user.ldif
