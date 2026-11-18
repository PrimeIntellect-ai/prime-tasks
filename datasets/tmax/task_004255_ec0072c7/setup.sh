#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/audit_logs.csv
U1,S1
S1,S2
U1,S2
U1,S3
S3,S2
U2,S3
S4,S5
U4,S4
U4,S5
U5,S1
S1,S5
U5,S5
S2,S9
U1,S9
S6,S7
U1,S6
U1,S7
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
