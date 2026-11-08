#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server_meta.json
[
  {"server_id": "srv-1", "region": "us-east-1", "tier": "web"},
  {"server_id": "srv-2", "region": "us-east-1", "tier": "db"},
  {"server_id": "srv-3", "region": "eu-west-1", "tier": "web"}
]
EOF

    cat << 'EOF' > /home/user/app_logs.csv
timestamp,server_id,log_level,message
2023-10-01T08:15:00Z,srv-1,INFO,Started process
2023-10-01T09:30:00Z,srv-1,ERROR,"NullPointerException
at line 42"
2023-10-01T10:05:00Z,srv-1,ERROR,Connection timeout
2023-10-01T10:45:00Z,srv-2,ERROR,Disk full
2023-10-01T10:55:00Z,srv-3,INFO,User login
2023-10-01T11:20:00Z,srv-1,ERROR,"SyntaxError
unexpected EOF"
2023-10-01T11:40:00Z,srv-3,ERROR,Timeout
2023-10-01T12:10:00Z,srv-4,ERROR,Unknown server dropped
EOF

    chmod -R 777 /home/user
