#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang curl jq openssl
    pip3 install pytest

    mkdir -p /home/user/certs

    cat << 'EOF' > /home/user/app-groups.conf
sudo:x:27:alice
web-admin:x:1001:bob
EOF

    cat << 'EOF' > /home/user/fw-rules.json
[
  {"port": 80, "action": "allow"}
]
EOF

    touch /home/user/provision.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
