#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/tx_logs.csv
1,100,50
2,101,60
3,100,60
4,101,50
5,102,10
6,103,20
7,102,20
8,103,10
9,104,80
10,105,90
11,104,90
12,105,80
13,106,100
14,107,110
15,106,110
16,107,100
17,108,120
18,109,130
19,108,130
20,109,120
EOF

    cat << 'EOF' > /tmp/expected_audit_report.txt
102,103,10,20
104,105,80,90
106,107,100,110
108,109,120,130
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
