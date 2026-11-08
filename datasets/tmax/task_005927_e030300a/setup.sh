#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyyaml

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/allocations.json
{
    "legacy_net": "172.16.0.0/16",
    "metrics_net": "10.10.10.0/24",
    "app_net": "192.168.1.0/24"
}
EOF

    cat << 'EOF' > /home/user/docker-compose.yml
version: "3"
services:
  analyzer:
    image: capacity-analyzer:latest
    networks:
      - new_metrics
networks:
  new_metrics:
    ipam:
      driver: default
      config:
        - subnet: 10.10.10.128/25
EOF

    chmod -R 777 /home/user
