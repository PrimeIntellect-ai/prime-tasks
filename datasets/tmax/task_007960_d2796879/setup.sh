#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_configs
    cat << 'EOF' > /home/user/raw_configs/server1.conf
# Main Configuration
host = 192.168.1.10
port=8080 # HTTP port

  # duplicate below
host = 192.168.1.10

timeout = 30
EOF

    cat << 'EOF' > /home/user/raw_configs/server2.conf
  loglevel=debug   # set log level

loglevel=debug
path=/var/log/app.log
EOF

    chmod -R 777 /home/user
