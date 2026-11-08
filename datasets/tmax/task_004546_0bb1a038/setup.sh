#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata gawk grep coreutils
    pip3 install pytest pytz

    mkdir -p /home/user/monitor/logs
    mkdir -p /home/user/backup

    cat << 'EOF' > /home/user/monitor/ss_output.txt
State    Recv-Q    Send-Q       Local Address:Port       Peer Address:Port    Process
LISTEN   0         4096         127.0.0.1:6379           0.0.0.0:*            users:(("redis-server",pid=112,fd=4))
LISTEN   0         4096         0.0.0.0:8080             0.0.0.0:*            users:(("nginx",pid=555,fd=6))
LISTEN   0         4096         0.0.0.0:22               0.0.0.0:*            users:(("sshd",pid=99,fd=3))
EOF

    cat << 'EOF' > /home/user/monitor/check_network.py
#!/usr/bin/env python3
import os
import subprocess

# Broken path
log_file = "./alert.log"

# TODO: Add grep/awk processing of /home/user/monitor/ss_output.txt
# TODO: Add timezone aware timestamp
# TODO: Write to absolute path and set permissions
EOF

    chmod 755 /home/user/monitor/check_network.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
