#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip faketime tzdata socat
    pip3 install pytest pytz

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/optimizer.service
[Unit]
Description=Cost Optimizer Port Forwarding

[Service]
ExecStart=/bin/false
EOF

    cat << 'EOF' > /home/user/port_mapping.json
{
    "db": {"listen": 5432, "target": 15432},
    "cache": {"listen": 6379, "target": 16379}
}
EOF

    chmod -R 777 /home/user
