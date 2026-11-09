#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget curl tar
    pip3 install pytest

    mkdir -p /home/user/data /home/user/output

    cat << 'EOF' > /home/user/data/logs.csv
id,timestamp,message
1,10:00,Error starting server
2,10:01,server is running
A,10:02,invalid row
3,10:03,Error error server
4,10:04,Connection timeout
5,10:05,server error timeout
EOF

    cat << 'EOF' > /home/user/data/vocab.txt
error
server
timeout
EOF

    cat << 'EOF' > /home/user/data/projection.csv
0.5,0.1
0.2,0.8
0.9,0.3
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
