#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gzip util-linux
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/quotas.json
[
  {"user": "alice", "used": 95, "limit": 100},
  {"user": "bob", "used": 50, "limit": 100},
  {"user": "charlie", "used": 950, "limit": 1000},
  {"user": "dave", "used": 90, "limit": 100},
  {"user": "eve", "used": 910, "limit": 1000},
  {"user": "frank", "used": 0, "limit": 500}
]
EOF

    gzip /home/user/quotas.json

    chmod -R 777 /home/user
