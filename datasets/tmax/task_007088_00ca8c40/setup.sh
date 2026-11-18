#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user/app_data/node1
    mkdir -p /home/user/app_data/node2
    mkdir -p /home/user/app_data/node3
    mkdir -p /home/user/config
    mkdir -p /home/user/scripts
    mkdir -p /home/user/logs

    # Create files to simulate disk usage
    dd if=/dev/zero of=/home/user/app_data/node1/data.bin bs=1M count=45
    dd if=/dev/zero of=/home/user/app_data/node2/data.bin bs=1M count=15
    dd if=/dev/zero of=/home/user/app_data/node3/data.bin bs=1M count=50

    # Create initial router.json
    cat << 'EOF' > /home/user/config/router.json
{
  "global_settings": {
    "timeout": 30,
    "retries": 3
  },
  "nodes": {
    "node1": {
      "path": "/home/user/app_data/node1",
      "status": "online"
    },
    "node2": {
      "path": "/home/user/app_data/node2",
      "status": "offline"
    },
    "node3": {
      "path": "/home/user/app_data/node3",
      "status": "online"
    }
  }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
