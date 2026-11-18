#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo espeak
    pip3 install pytest

    # Create the Rust project
    mkdir -p /home/user
    cd /home/user
    cargo new loc_etl

    # Create the audio file
    mkdir -p /app
    espeak -w /app/audio_instructions.wav "Drop any record where the text contains the exact string REJECTED in all caps."

    # Create the reference binary (using Python for simplicity)
    cat << 'EOF' > /app/reference_dedup
#!/usr/bin/env python3
import sys
import json

data = {}
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        record = json.loads(line)
        if '\uFFFD' in record['text'] or 'REJECTED' in record['text']:
            continue
        key = record['key']
        lang = record['lang']
        ts = record['timestamp']
        text = record['text']

        if key not in data:
            data[key] = {}
        if lang not in data[key]:
            data[key][lang] = (ts, text)
        else:
            if ts >= data[key][lang][0]:
                data[key][lang] = (ts, text)
    except Exception:
        pass

output = {}
for key in sorted(data.keys()):
    if not data[key]:
        continue
    output[key] = {}
    for lang in sorted(data[key].keys()):
        output[key][lang] = data[key][lang][1]

print(json.dumps(output, separators=(',', ':')))
EOF
    chmod +x /app/reference_dedup

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
