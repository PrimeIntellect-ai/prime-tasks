#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_translations.jsonl
{"ts": "2023-10-01T10:00:00Z", "lang": "es", "chars": 50, "status": "approved"}
{"ts": "2023-10-01T10:01:00Z", "lang": "es", "chars": -10, "status": "approved"}
{"ts": "2023-10-01T10:02:00Z", "lang": "fr", "chars": 100, "status": "draft"}
{"ts": "2023-10-01T10:03:00Z", "lang": "es", "chars": 40, "status": "approved"}
{"ts": "2023-10-01T10:04:00Z", "lang": "es", "chars": 60, "status": "approved"}
{"ts": "2023-10-01T10:05:00Z", "lang": "fr", "chars": 200, "status": "approved"}
{"ts": "2023-10-01T10:06:00Z", "lang": "es", "chars": 80, "status": "approved"}
{"ts": "2023-10-01T10:07:00Z", "lang": "fr", "chars": 150, "status": "approved"}
{"ts": "2023-10-01T10:08:00Z", "lang": "fr", "chars": 100, "status": "approved"}
{"ts": "2023-10-01T10:09:00Z", "lang": "fr", "chars": 300, "status": "approved"}
EOF

    chmod -R 777 /home/user
