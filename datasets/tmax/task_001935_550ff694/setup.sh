#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget ffmpeg espeak
    pip3 install pytest

    # Install Go 1.21+
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    ln -s /usr/local/go/bin/go /usr/bin/go
    ln -s /usr/local/go/bin/gofmt /usr/bin/gofmt
    rm go1.21.6.linux-amd64.tar.gz

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate baseline audio memo
    espeak -w /app/baseline_memo.wav "The calibration matrix baseline values are: forty-two point seven, negative zero point zero zero three, and eight hundred and twelve."

    # Generate corpus JSON files
    cat << 'EOF' > /tmp/generate_corpus.py
import json
import os

# Clean 1
clean1 = [
    {"id": "1", "parent_id": "", "duration_ns": 100.0, "invocations": 1},
    {"id": "2", "parent_id": "1", "duration_ns": 50.0, "invocations": 2}
]
with open('/app/corpus/clean/clean1.json', 'w') as f: json.dump(clean1, f)

# Evil 1: cycle
evil1 = [
    {"id": "1", "parent_id": "2", "duration_ns": 100.0, "invocations": 1},
    {"id": "2", "parent_id": "1", "duration_ns": 50.0, "invocations": 2}
]
with open('/app/corpus/evil/evil1.json', 'w') as f: json.dump(evil1, f)

# Evil 2: invocations: 0
evil2 = [
    {"id": "1", "parent_id": "", "duration_ns": 100.0, "invocations": 0}
]
with open('/app/corpus/evil/evil2.json', 'w') as f: json.dump(evil2, f)

# Evil 3: duration_ns < 0
evil3 = [
    {"id": "1", "parent_id": "", "duration_ns": -50.0, "invocations": 1}
]
with open('/app/corpus/evil/evil3.json', 'w') as f: json.dump(evil3, f)

# Evil 4: missing fields
evil4 = [
    {"id": "1", "parent_id": ""}
]
with open('/app/corpus/evil/evil4.json', 'w') as f: json.dump(evil4, f)
EOF
    python3 /tmp/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
