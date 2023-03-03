#!/bin/bash

echo "Deploying to S3 Bucket..."
aws s3 cp --acl public-read ../cloudformation/openondemand.yml s3://aws-hpc-workshops
