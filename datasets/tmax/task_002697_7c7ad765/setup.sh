#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_configs.txt
5,40,110,160
15,45,105,155
35,60,90,140
90,80,70,120
EOF

    chmod -R 777 /home/user
