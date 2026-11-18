#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/stream.txt
10
12
11
10
13
15
50
12
14
16
15
100
10
11
EOF

    chmod -R 777 /home/user
