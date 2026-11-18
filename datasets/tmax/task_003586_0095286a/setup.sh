#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq binutils
    pip3 install pytest pyinstaller

    mkdir -p /app
    cat << 'EOF' > /app/ingest.py
import sys
import json

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        log = json.loads(line)
        event_class = log.get("event_class", "")
        if event_class == "OOM":
            _id = log.get("remediation_id")
            if _id is None:
                # Simulate rust panic
                print("thread 'main' panicked at 'called `Option::unwrap()` on a `None` value'", file=sys.stderr)
                sys.exit(101)
    except Exception:
        pass
EOF

    cd /app
    pyinstaller --onefile ingest.py
    mv dist/ingest /app/telemetry_ingest
    strip /app/telemetry_ingest
    rm -rf build dist ingest.py ingest.spec

    mkdir -p /home/user/raw_logs
    mkdir -p /app/verifier_corpus/evil
    mkdir -p /app/verifier_corpus/clean

    cat << 'EOF' > /app/generate_data.py
import json
import os
import random

random.seed(42)

for i in range(50):
    with open(f'/home/user/raw_logs/log_{i}.jsonl', 'w') as f:
        for _ in range(20):
            if i < 5 and random.random() < 0.2:
                f.write(json.dumps({"event_class": "OOM", "remediation_id": None, "timestamp": 1670000000}) + '\n')
            else:
                f.write(json.dumps({"event_class": "OK", "remediation_id": 123, "timestamp": 1670000000}) + '\n')

with open('/app/verifier_corpus/evil/evil.jsonl', 'w') as f:
    for _ in range(50):
        f.write(json.dumps({"event_class": "OOM", "remediation_id": None, "timestamp": 1670000000}) + '\n')

with open('/app/verifier_corpus/clean/clean.jsonl', 'w') as f:
    for _ in range(50):
        f.write(json.dumps({"event_class": "OOM", "remediation_id": 123, "timestamp": 1670000000}) + '\n')
        f.write(json.dumps({"event_class": "NETWORK", "remediation_id": None, "timestamp": 1670000000}) + '\n')
EOF

    python3 /app/generate_data.py
    rm /app/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
