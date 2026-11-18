#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest PyJWT

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    espeak -w /app/intercepted_comms.wav "The emergency signing key is bravo tango seven four niner omega"

    cat << 'EOF' > /tmp/setup.py
import jwt
import os

secret = "bravo tango seven four niner omega"
evil_secret = "wrong secret"

for i in range(50):
    payload = {"user": f"user{i}", "admin": False}
    # Clean
    token = jwt.encode(payload, secret, algorithm="HS256")
    with open(f"/app/corpus/clean/token_{i}.txt", "w") as f:
        f.write(token)

    # Evil
    evil_token = jwt.encode(payload, evil_secret, algorithm="HS256")
    with open(f"/app/corpus/evil/token_{i}.txt", "w") as f:
        f.write(evil_token)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
