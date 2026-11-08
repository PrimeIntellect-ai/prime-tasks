#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq
    pip3 install pytest

    mkdir -p /home/user/workspace/configs

    cat << 'EOF' > /home/user/workspace/configs/baseline.txt
port=8080
max_connections=100
mode=prod
EOF

    cat << 'EOF' > /home/user/workspace/configs/server1.json
{
  "port": 8080,
  "max_connections": 100,
  "mode": "dev"
}
EOF

    cat << 'EOF' > /home/user/workspace/configs/server2.ini
[network]
port=8081

[limits]
max_connections=150

[app]
mode=prod
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
