#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/calculator
    cat << 'EOF' > /home/user/calculator/input.txt
10 + 5 - 3
100 - 20 - 5 + 1
42 + 8
7 - 10 + 2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
