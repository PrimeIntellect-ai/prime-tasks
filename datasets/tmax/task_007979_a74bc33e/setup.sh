#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/org_chart.json
{
  "id": "E01",
  "name": "Alice",
  "subordinates": [
    {
      "id": "E02",
      "name": "Bob",
      "subordinates": [
        {
          "id": "E04",
          "name": "Dave",
          "subordinates": []
        }
      ]
    },
    {
      "id": "E03",
      "name": "Charlie",
      "subordinates": [
        {
          "id": "E05",
          "name": "Eve",
          "subordinates": []
        }
      ]
    }
  ]
}
EOF

    cat << 'EOF' > /home/user/access_logs.json
[
  {"user_id": "E04", "timestamp": "2023-10-01T10:00:00Z", "action": "download", "bytes": 2000},
  {"user_id": "E04", "timestamp": "2023-10-01T10:05:00Z", "action": "download", "bytes": 2000},
  {"user_id": "E04", "timestamp": "2023-10-01T10:12:00Z", "action": "download", "bytes": 2000},
  {"user_id": "E04", "timestamp": "2023-10-01T10:25:00Z", "action": "download", "bytes": 4000},
  {"user_id": "E05", "timestamp": "2023-10-01T10:05:00Z", "action": "download", "bytes": 3000},
  {"user_id": "E05", "timestamp": "2023-10-01T10:10:00Z", "action": "download", "bytes": 3000},
  {"user_id": "E05", "timestamp": "2023-10-01T10:10:00Z", "action": "blocked", "bytes": 10000},
  {"user_id": "E02", "timestamp": "2023-10-01T11:00:00Z", "action": "download", "bytes": 6000}
]
EOF

    chmod 644 /home/user/org_chart.json
    chmod 644 /home/user/access_logs.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
