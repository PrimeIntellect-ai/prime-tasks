#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.csv
1620000000,S-001,25.5,OK
1620000001,S-002,-60.0,OK
1620000002,X-001,20.0,OK
1620000003,S-001,27.5,OK
1620000004,S-003,15.0,ERR
invalid,S-001,20.0,OK
1620000005,S-002,10.0,OK
1620000006,S-002,12.0,OK
1620000007,S-004,50.1,OK
1620000008,S-004,49.9,OK
1620000009,S-001,40.0,ERR
1620000010,S-005,-50.0,OK
1620000011,S-005,10.0,OK
1620000012,S-005,bad,OK
1620000013,S-005,0.0,OK
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
