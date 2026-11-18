#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    espeak -w /app/legacy_passcode.wav "The passcode is alfa bravo seven three nine nine"

    cat << 'EOF' > /app/auth_logs.txt
[INFO] System startup complete.
[WARN] Deprecated API accessed.
[INFO] Rotation salt for today is xZ99Pq
[DEBUG] Flushing cache.
EOF

    cat << 'EOF' > /tmp/generate_tokens.py
import hashlib
import base64
import os

old_passcode = "ab7399"
salt = "xZ99Pq"
new_seed = hashlib.sha256((old_passcode + salt).encode()).hexdigest()

def make_token(payload, seed):
    b64_payload = base64.b64encode(payload.encode()).decode()
    sig = hashlib.sha256((seed + b64_payload).encode()).hexdigest()
    return f"{b64_payload}.{sig}"

# Clean
with open("/app/corpus/clean/clean_1.tok", "w") as f:
    f.write(make_token("user:admin", new_seed))
with open("/app/corpus/clean/clean_2.tok", "w") as f:
    f.write(make_token("user:guest", new_seed))

# Evil 1: Malicious payload
with open("/app/corpus/evil/evil_1.tok", "w") as f:
    f.write(make_token("user:admin<script>alert(1)</script>", new_seed))

# Evil 2: Old signature
with open("/app/corpus/evil/evil_2.tok", "w") as f:
    f.write(make_token("user:admin", old_passcode))

# Evil 3: Bad signature
with open("/app/corpus/evil/evil_3.tok", "w") as f:
    b64_payload = base64.b64encode(b"user:admin").decode()
    bad_sig = "a" * 64
    f.write(f"{b64_payload}.{bad_sig}")

# Evil 4: Malicious payload case insensitive
with open("/app/corpus/evil/evil_4.tok", "w") as f:
    f.write(make_token("user:admin<SCRIPT>alert(1)</SCRIPT>", new_seed))

EOF

    python3 /tmp/generate_tokens.py
    rm /tmp/generate_tokens.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
