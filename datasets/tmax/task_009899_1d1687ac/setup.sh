#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/libs.csv
core,50
math,30
net,25
ui,80
db,120
crypto,45
EOF

    chmod -R 777 /home/user
