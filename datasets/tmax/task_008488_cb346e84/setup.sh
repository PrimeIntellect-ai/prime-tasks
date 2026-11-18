#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq nasm binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/deps.json
{
  "nodes": [5, 12, 18, 24, 33],
  "edges": [
    {"from": 5, "to": 12},
    {"from": 5, "to": 18},
    {"from": 12, "to": 33},
    {"from": 18, "to": 12},
    {"from": 18, "to": 24},
    {"from": 24, "to": 5},
    {"from": 24, "to": 33},
    {"from": 33, "to": 18},
    {"from": 33, "to": 5}
  ]
}
EOF

    chmod -R 777 /home/user
