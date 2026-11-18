#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/etl_output

    cat << 'EOF' > /home/user/raw_data/stream1.csv
time,sensor,temp
2023-11-01T08:15:30Z,A,10.0
2023-11-01T08:45:00Z,A,12.0
2023-11-01T08:45:00Z,A,12.0
2023-11-01T08:50:00Z,B,
2023-11-01T09:10:00Z,A,15.0
2023-11-01T09:15:00Z,C,10.5
2023-11-01T09:15:00Z,C,10.5
2023-11-01T10:05:00Z,A,
EOF

    cat << 'EOF' > /home/user/raw_data/stream2.jsonl
{"ts":"2023-11-01T08:20:00Z","id":"B","v":20.0}
{"ts":"2023-11-01T08:40:00Z","id":"B","v":22.0}
{"ts":"2023-11-01T09:05:00Z","id":"B","v":null}
{"ts":"2023-11-01T09:15:00Z","id":"B","v":25.0}
{"ts":"2023-11-01T08:20:00Z","id":"B","v":20.0}
{"ts":"2023-11-01T10:15:00Z","id":"C","v":11.5}
EOF

    chmod -R 777 /home/user
