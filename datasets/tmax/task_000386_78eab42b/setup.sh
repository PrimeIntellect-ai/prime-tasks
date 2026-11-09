#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/raw_data
    cat << 'EOF' > /home/user/raw_data/retried_logs.json
[
  {
    "timestamp": 1682859321,
    "user": "alice",
    "action": "login",
    "ingestion_time": "2023-04-30T13:00:00Z"
  },
  {
    "timestamp": "2023-04-30T12:55:21Z",
    "user": "alice",
    "action": "login",
    "ingestion_time": "2023-04-30T13:10:00Z"
  },
  {
    "timestamp": "2023/04/30 13:00:00",
    "user": "bob",
    "action": "upload",
    "ingestion_time": "2023-04-30T13:05:00Z"
  },
  {
    "timestamp": 1682863200,
    "user": "charlie",
    "action": "logout",
    "ingestion_time": "2023-04-30T14:15:00Z"
  },
  {
    "timestamp": "2023-04-30T13:00:00Z",
    "user": "bob",
    "action": "upload",
    "ingestion_time": "2023-04-30T14:10:00Z"
  },
  {
    "timestamp": "1682859325",
    "user": "alice",
    "action": "view_dashboard",
    "ingestion_time": "2023-04-30T13:01:00Z"
  }
]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/raw_data
    chmod -R 777 /home/user
