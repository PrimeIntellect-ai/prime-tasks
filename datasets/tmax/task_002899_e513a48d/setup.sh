#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/releases/service_a_v1
    mkdir -p /home/user/releases/service_a_v2
    mkdir -p /home/user/releases/service_b_v1
    mkdir -p /home/user/releases/service_b_v2
    mkdir -p /home/user/deployments/service_a
    mkdir -p /home/user/deployments/service_b
    mkdir -p /home/user/backups
    mkdir -p /home/user/run

    echo "v1 a" > /home/user/releases/service_a_v1/index.html
    echo "v2 a" > /home/user/releases/service_a_v2/index.html
    echo "v1 b" > /home/user/releases/service_b_v1/index.html
    echo "v2 b" > /home/user/releases/service_b_v2/index.html

    ln -s /home/user/releases/service_a_v1 /home/user/deployments/service_a/current
    ln -s /home/user/releases/service_b_v1 /home/user/deployments/service_b/current

    cat << 'EOF' > /home/user/services.json
{
  "service_a": {
    "host": "0.0.0.0",
    "port": 80
  },
  "service_b": {
    "host": "0.0.0.0",
    "port": 80
  }
}
EOF

    chmod -R 777 /home/user
