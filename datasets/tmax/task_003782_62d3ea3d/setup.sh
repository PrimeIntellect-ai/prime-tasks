#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_changes.log
2024-05-01 00:15:32,nginx,RELOAD,SUCCESS
2024-05-01 00:45:11,iptables,ADD,FAIL
2024-05-01 01:10:00,sshd,RESTART,SUCCESS
2024-05-01 01:22:10,sshd,UPDATE,SUCCESS
2024-05-01 03:05:01,docker,START,SUCCESS
2024-05-01 05:59:59,kubelet,STOP,SUCCESS
INVALID LINE 1
2024-05-01 06:00:00,nginx,RELOAD,SUCCESS
2024-05-01 02:XX:00,bad,BAD,SUCCESS
EOF

    chmod -R 777 /home/user
