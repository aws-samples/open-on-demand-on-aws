#!/bin/bash

# Create private key
openssl genrsa -out my-private-key.pem 2048

# Create CSR
openssl req -new -key my-private-key.pem -out my-csr.pem

# Create a self-signed certificate
openssl x509 -req -days 365 -in my-csr.pem -signkey my-private-key.pem -out my-certificate.pem

# Create a PEM bundle
cat my-private-key.pem my-certificate.pem > my-bundle.pem

# Create a PKCS12 bundle
openssl pkcs12 -export -out my-bundle.p12 -inkey my-private-key.pem -in my-certificate.pem

# Import certificate into AWS ACM
aws acm import-certificate \
  --certificate fileb://my-certificate.pem \
  --private-key fileb://my-private-key.pem \
  --region your-aws-region
