#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential sqlite3
    pip3 install pytest

    mkdir -p /home/user/workspace
    cat << 'EOF' > /home/user/workspace/clinical_data.csv
ID,FullName,Email,M1_BP,M2_BP,M3_BP
101,Alice Smith,alice@example.com,120,118,-5
102,Bob Jones,bob@j.com,130,0,140
103,Charlie,charlie@foo.com,-10,-20,-30
104,Diana Prince,diana@aws.com,115,116,117
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
