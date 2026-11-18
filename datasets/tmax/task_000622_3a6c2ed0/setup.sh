#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcat-openbsd gcc
    pip3 install pytest

    mkdir -p /home/user/netmon

    cat << 'EOF' > /home/user/netmon/valid_users.txt
alice
bob
EOF

    cat << 'EOF' > /home/user/netmon/services.conf
8081:alice
8082:bob
8083:charlie
8084:alice
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
