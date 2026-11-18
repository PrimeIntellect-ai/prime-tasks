#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/metrics.jsonl
{"timestamp": 1, "server": "srv1", "cpu": 10.0}
{"timestamp": 2, "server": "srv1", "cpu": 20.0}
{"timestamp": 3, "server": "srv2", "cpu": 50.0}
{"timestamp": 4, "server": "srv1", "cpu": 99.0, "tag": "\u00"}
{"timestamp": 5, "server": "srv1", "cpu": 30.0}
{"timestamp": 6, "server": "srv2", "cpu": 60.0}
{"timestamp": 7, "server": "srv3", "cpu": 10.0, "bad": "escap\e"}
EOF

    cat << 'EOF' > /home/user/server_info.csv
server,role
srv1,web
srv2,db
srv3,cache
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
