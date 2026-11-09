#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/config_changes.log
[2023-10-01T12:00:00Z] USER: admin KEY: Network Setup VALUE: Interface eth0 up
[2023-10-01T12:05:00Z] USER: sys KEY: Database
Connection VALUE: Retrying
timeout
[2023-10-01T12:10:00Z] USER: admin KEY: Firewall Rule VALUE: Block port 80
[2023-10-01T12:15:00Z] USER: dev KEY:   Cache 
   Servers   VALUE: flushed
all
nodes
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
