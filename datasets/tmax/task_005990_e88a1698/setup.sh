#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
record_id,email,Q1_score,Q2_score,Q3_score,Q4_score,timestamp
101,alice.smith@company.com,85,90,95,100,1620000000
102,bob.jones@domain.org,70,,80,105,1620000100
101,alice.smith@company.com,85,92,95,100,1620000200
103,charlie.c@startup.io,50,-5,60,70,1620000050
104,david.d@enterprise.net,,,,100,1620000300
102,bob.jones@domain.org,70,75,80,105,1620000050
EOF

    chmod -R 777 /home/user
