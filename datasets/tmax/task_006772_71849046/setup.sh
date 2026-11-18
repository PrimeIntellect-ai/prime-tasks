#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/configs/

    cat << 'EOF' > /home/user/configs/config_2023-10-01T00.txt
# Initial config
SERVER=localhost
PORT=8080
TIMEOUT=30
EOF

    cat << 'EOF' > /home/user/configs/config_2023-10-01T02.txt
# Updated config
server=localhost
PORT=8081
MAX_CONN=100
EOF

    cat << 'EOF' > /home/user/configs/config_2023-10-01T05.txt
SERVER=127.0.0.1
PORT=8081
MAX_CONN=100
# Testing
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
