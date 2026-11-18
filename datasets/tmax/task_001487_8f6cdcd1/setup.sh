#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.jsonl
{"ts": 1, "path": "/api/data", "time": 10, "msg": "ok"}
{"ts": 2, "path": "/api/data", "time": 20, "msg": "bad unicode \u12G4"}
{"ts": 3, "path": "/api/data", "time": 30, "msg": "ok"}
{"ts": 4, "path": "/api/data", "time": 50, "msg": "ok"}
{"ts": 5, "path": "/api/data", "time": 10, "msg": "ok"}
{"ts": 6, "path": "/api/other", "time": 100, "msg": "short unicode \u12"}
{"ts": 7, "path": "/api/data", "time": 60, "msg": "valid unicode \u1234"}
{"ts": 8, "path": "/api/other", "time": 5, "msg": "ok"}
EOF

    chmod -R 777 /home/user
