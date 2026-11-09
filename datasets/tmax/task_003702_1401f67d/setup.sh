#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.json
[
  {
    "session_id": "sess_001",
    "client_ip": "192.168.1.45",
    "user_id": "user_492",
    "events": [
      {
        "timestamp": "2023-10-01T10:00:00Z",
        "event_type": "view",
        "request": "GET /api/v1/items/882 HTTP/1.1"
      },
      {
        "timestamp": "2023-10-01T10:05:00Z",
        "event_type": "click",
        "request": "POST /api/v1/items/882/buy HTTP/1.1"
      }
    ]
  },
  {
    "session_id": "sess_002",
    "client_ip": "10.0.0.99",
    "user_id": "user_111",
    "events": [
      {
        "timestamp": "2023-10-01T09:15:00Z",
        "event_type": "login",
        "request": "POST /auth/login HTTP/1.1"
      }
    ]
  }
]
EOF

    chmod -R 777 /home/user
