#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest hypothesis

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/ws_stream.txt
DEVICE=A1B2;DATA=100
DEVICE=A1B2;DATA=200
DEVICE=A1B2;DATA=300
DEVICE=A1B2;DATA=400
DEVICE=FFFF;DATA=5
DEVICE=fff;DATA=10
DEVICE=A1B2; DATA=100
DEVICE=1234;DATA=99999999
EOF

    chmod -R 777 /home/user
