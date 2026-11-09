#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/src
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/telemetry.log
2023-10-12T08:14:55Z | S100 | 45.2 | status="active"
2023-10-12T08:15:12Z | S102 | 85.0 | status="overheating\u26A0"
2023-10-12T08:15:59Z | S101 | 12.1 | status="ok\u2713"
2023-10-12T08:16:01Z | S100 | -25.4 | status="error"
2023-10-12T08:16:30Z | S103 | 59.9 | status="warn\u0021"
EOF

    cat << 'EOF' > /tmp/expected.csv
timestamp,sensor,temperature,status
2023-10-12T08:14:00Z,S100,45.2,active
2023-10-12T08:15:00Z,S101,12.1,ok
2023-10-12T08:16:00Z,S103,59.9,warn
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
