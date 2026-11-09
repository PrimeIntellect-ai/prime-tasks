#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input_logs.csv
log_id,timestamp,message
1,2023-10-01T10:00:00Z,Hello Wörld!
2,2023-10-01T10:00:05Z,This is a test.
3,2023-10-01T10:00:10Z,Hello Wörld!
4,2023-10-01T10:00:15Z,Another message here...
5,2023-10-01T10:00:20Z,this is a test.
6,2023-10-01T10:01:00Z,Data engineering is fún!!
7,2023-10-01T10:02:00Z,hello world
8,2023-10-02T10:00:00Z,Final message.
EOF

    chmod -R 777 /home/user
