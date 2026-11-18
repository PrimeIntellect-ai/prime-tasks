#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/corpora/evil /app/corpora/clean

    espeak -w /app/intercept.wav "base sixty four reverse then xor fifty five"

    cat << 'EOF' > /tmp/setup_corpora.py
import base64
import os

def encode(text):
    xored = bytes([b ^ 0x55 for b in text.encode('utf-8')])
    reversed_bytes = xored[::-1]
    return base64.b64encode(reversed_bytes).decode('utf-8')

evil_payloads = [
    '<script src="http://attacker.com/bypass.js" nonce="fixed_nonce">',
    "script-src 'unsafe-inline' 'unsafe-eval'",
    "object-src 'none'; script-src http://evil.com"
]

clean_payloads = [
    "default-src 'self'; img-src https://trusted.com;",
    "script-src 'self' https://apis.google.com",
    "default-src 'none'; script-src 'self'"
]

for i, p in enumerate(evil_payloads):
    with open(f'/app/corpora/evil/payload_{i}.txt', 'w') as f:
        f.write(encode(p))

for i, p in enumerate(clean_payloads):
    with open(f'/app/corpora/clean/payload_{i}.txt', 'w') as f:
        f.write(encode(p))
EOF

    python3 /tmp/setup_corpora.py
    rm /tmp/setup_corpora.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
