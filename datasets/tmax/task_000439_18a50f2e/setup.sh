#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/configs.csv
server_id,timestamp,raw_config
srv-alpha,1700001,"max_workers=4
timeout=30"
srv-beta,1700002,"MAX_WORKERS=4
TIMEOUT=30 "
srv-gamma,1700003,"max_workers=8
timeout=60"
srv-delta,1700004," max_workers = 4
timeout = 30
"
srv-epsilon,1700005,"max_workers=8
timeout=60"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
