#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_edits.jsonl
{"timestamp": "2023-10-01T08:15:00Z", "locale": "fr-FR", "words": 100, "tm_match": 80}
{"timestamp": "2023-10-01T08:45:00Z", "locale": "fr-FR", "words": 50, "tm_match": 100}
{"timestamp": "2023-10-01T08:10:00Z", "locale": "de-DE", "words": 200, "tm_match": 90}
{"timestamp": "2023-10-01T10:20:00Z", "locale": "es-ES", "words": 200, "tm_match": 50}
{"timestamp": "2023-10-01T12:05:00Z", "locale": "fr-FR", "words": 10, "tm_match": 0}
EOF

    chmod -R 777 /home/user
