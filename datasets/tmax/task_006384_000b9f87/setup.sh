#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/reference.csv
p,P_theo
0.4,0.05
0.5,0.25
0.55,0.50
0.6,0.75
EOF
    chmod 644 /home/user/reference.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
