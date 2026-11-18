#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
{"timestamp": "2023-10-01T10:00:01", "service": "auth", "status": 200}
2023-10-01T10:00:02,auth,500
2023-10-01T10:00:03,auth,200
{"timestamp": "2023-10-01T10:00:04", "service": "auth", "status": 503}
2023-10-01T10:00:05,db,200
{"timestamp": "2023-10-01T10:00:06", "service": "db", "status": 404}
2023-10-01T10:00:07,db,INVALID
{"timestamp": "2023-10-01T10:00:08", "service": "db", "status": 200}
2023-10-01T10:00:02,payment,20
{"timestamp": "2023-10-01T10:00:09", "service": "db", "status": 200}
EOF

    chmod -R 777 /home/user
