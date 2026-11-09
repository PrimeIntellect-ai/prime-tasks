#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bash
    pip3 install pytest matplotlib

    mkdir -p /home/user

    cat << 'EOF' > /home/user/features.txt
-1.0
0.0
1.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
