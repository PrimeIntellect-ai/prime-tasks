#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc openssl curl
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/data/usage.csv
1670000000,45.50,1024.00
1670000060,55.00,2048.00
1670000120,60.50,1536.00
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
