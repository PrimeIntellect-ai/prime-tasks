#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /opt
    cat << 'EOF' > /opt/embedder.py
import sys
import json

if len(sys.argv) < 2:
    print("[0, 0, 0]")
    sys.exit(0)

text = sys.argv[1]
length = len(text)
vowels = sum(1 for c in text.lower() if c in 'aeiou')
consonants = sum(1 for c in text.lower() if c in 'bcdfghjklmnpqrstvwxyz')

print(json.dumps([length, vowels, consonants]))
EOF
    chmod +x /opt/embedder.py

    cat << 'EOF' > /home/user/raw_data.jsonl
{"id": 10, "text": "Great product", "label": "POSITIVE"}
{"id": 15, "text": "Terrible experience", "label": "NEGATIVE"}
{"id": "2", "text": "String ID invalid", "label": "POSITIVE"}
{"id": 8, "text": "Missing label"}
{"id": 3, "text": "Okay", "label": "NEUTRAL"}
{"id": 12, "text": "Loved it", "label": "POSITIVE"}
{"id": 5, "text": "Not bad", "label": "POSITIVE"}
{"id": 20, "text": "Worst thing ever", "label": "NEGATIVE"}
{"id": 1, "text": "Awesome", "label": "POSITIVE"}
{"id": 7, "text": "Hated it", "label": "NEGATIVE"}
{"id": 25, "text": 12345, "label": "POSITIVE"}
EOF

    chmod -R 777 /home/user
