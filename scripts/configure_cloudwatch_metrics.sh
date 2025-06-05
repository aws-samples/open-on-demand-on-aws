#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

STACK_NAME=$1
RETENTION_DAYS=${2:-30}

cat << EOF > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
        "agent": {
                "metrics_collection_interval": 60,
                "run_as_user": "root"
        },
        "logs": {
                "logs_collected": {
                        "files": {
                                "collect_list": [
                                        {
                                                "file_path": "/var/log/slurm/slurmd.log",
                                                "log_group_name": "${STACK_NAME}",
                                                "log_stream_name": "{instance_id}/slurmd.log",
                                                "retention_in_days": ${RETENTION_DAYS}
                                        },
                                        {
                                                "file_path": "/var/log/sbatch.log",
                                                "log_group_name": "${STACK_NAME}",
                                                "log_stream_name": "{instance_id}/sbatch.log",
                                                "retention_in_days": ${RETENTION_DAYS}
                                        },
                                        {
                                                "file_path": "/var/log/ondemand-nginx/**",
                                                "log_group_name": "${STACK_NAME}",
                                                "log_stream_name": "{instance_id}/ondemand-nginx",
                                                "retention_in_days": ${RETENTION_DAYS}
                                        },
                                        {
                                                "file_path": "/var/log/httpd/**",
                                                "log_group_name": "${STACK_NAME}",
                                                "log_stream_name": "{instance_id}/ondemand-httpd",
                                                "retention_in_days": ${RETENTION_DAYS}
                                        },
                                        {
                                                "file_path": "/var/log/cfn-init.log",
                                                "log_group_name": "${STACK_NAME}",
                                                "log_stream_name": "{instance_id}/cfn-init.log"
                                        },
                                        {
                                                "file_path": "/var/log/cfn-init-cmd.log",
                                                "log_group_name": "${STACK_NAME}",
                                                "log_stream_name": "{instance_id}/cfn-init-cmd.log"
                                        }                                        
                                ]
                        }
                }
        },
        "metrics": {
                "append_dimensions": {
                        "AutoScalingGroupName": "\${aws:AutoScalingGroupName}",
                        "InstanceId": "\${aws:InstanceId}"
                },
                "metrics_collected": {
                        "cpu": {
                                "measurement": [
                                        "cpu_usage_idle",
                                        "cpu_usage_iowait",
                                        "cpu_usage_user",
                                        "cpu_usage_system"
                                ],
                                "metrics_collection_interval": 60,
                                "resources": [
                                        "*"
                                ],
                                "totalcpu": false
                        },
                        "disk": {
                                "measurement": [
                                        "used_percent",
                                        "inodes_free"
                                ],
                                "metrics_collection_interval": 60,
                                "resources": [
                                        "*"
                                ]
                        },
                        "diskio": {
                                "measurement": [
                                        "io_time"
                                ],
                                "metrics_collection_interval": 60,
                                "resources": [
                                        "*"
                                ]
                        },
                        "mem": {
                                "measurement": [
                                        "mem_used_percent"
                                ],
                                "metrics_collection_interval": 60
                        },
                        "swap": {
                                "measurement": [
                                        "swap_used_percent"
                                ],
                                "metrics_collection_interval": 60
                        }
                }
        }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
