#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
pip3 install pytest

mkdir -p /app

# Generate the audio file
espeak -w /app/sysadmin_voicemail.wav "Hey, so the old configs are in cp1252 encoding, not UTF-8. They use a bracket config header. Keys and values are separated by a pipe symbol. Oh, and any key that starts with SECURE underscore needs to have its value reversed string-wise before we put it in the JSON. Output should be a JSON object mapping keys to values."

# Create the oracle parser
cat << 'EOF' > /app/oracle_parser.py
import sys
import json

def parse():
    raw = sys.stdin.buffer.read()
    text = raw.decode('cp1252')
    lines = text.splitlines()

    data = {}
    for line in lines:
        line = line.strip()
        if not line or line.startswith('['):
            continue
        if '|' in line:
            k, v = line.split('|', 1)
            if k.startswith('SECURE_'):
                v = v[::-1]
            data[k] = v

    print(json.dumps(data, separators=(',', ':')))

if __name__ == '__main__':
    parse()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
