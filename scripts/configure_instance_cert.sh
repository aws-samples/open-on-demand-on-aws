# /bin/bash
# Creates self signed cert for use by OOD
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

mkdir -p /etc/ssl/private
chmod 700 /etc/ssl/private
mkdir -p /etc/ssl/certs

openssl req -nodes -new -x509  -keyout /etc/ssl/private/private_key.key -out /etc/ssl/private/cert.crt \
-subj "/C=US/O=OOD/CN=test.com"
