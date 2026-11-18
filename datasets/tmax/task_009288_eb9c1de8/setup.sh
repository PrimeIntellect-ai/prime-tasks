#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access_log.json
[
  {"user": "u1", "time": 100},
  {"user": "u2", "time": 200},
  {"user": "u1", "time": 102},
  {"user": "u1", "time": 104},
  {"user": "u1", "time": 106},
  {"user": "u1", "time": 108},
  {"user": "u3", "time": 300},
  {"user": "u3", "time": 301},
  {"user": "u3", "time": 302},
  {"user": "u3", "time": 303},
  {"user": "u3", "time": 304},
  {"user": "u4", "time": 400},
  {"user": "u4", "time": 403},
  {"user": "u4", "time": 406},
  {"user": "u4", "time": 409},
  {"user": "alice", "time": 500},
  {"user": "alice", "time": 502},
  {"user": "alice", "time": 504},
  {"user": "alice", "time": 506},
  {"user": "alice", "time": 508},
  {"user": "bob", "time": 600},
  {"user": "bob", "time": 605},
  {"user": "bob", "time": 610},
  {"user": "bob", "time": 615},
  {"user": "bob", "time": 620}
]
EOF

    chmod -R 777 /home/user
