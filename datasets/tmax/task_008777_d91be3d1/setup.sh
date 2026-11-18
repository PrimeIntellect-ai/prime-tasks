#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest --default-timeout=100

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_events.csv
user_id,session_id
U1,S1
U2,S1
U3,S1
U4,S1
U4,S2
U5,S2
U6,S2
U1,S3
U7,S3
U8,S4
U9,S4
U10,S4
U11,S4
U12,S4
U8,S5
U13,S5
U14,S5
EOF

    chmod -R 777 /home/user
