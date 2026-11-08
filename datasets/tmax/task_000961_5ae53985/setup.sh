#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/cpu.csv
1700000000,10
1700000005,25
1700000010,85
1700000015,30
1700000020,85
1700000025,90
EOF

    cat << 'EOF' > /home/user/mem.csv
1700000020,95
1700000000,50
1700000010,92
1700000005,60
1700000015,40
1700000025,80
EOF

    chmod -R 777 /home/user
