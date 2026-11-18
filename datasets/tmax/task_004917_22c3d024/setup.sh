#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate tokens
    python3 -c '
import os
import json
import base64
import hashlib

secret = b"crimson_dynamo_88"

def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

def sign(payload_b64, sec):
    return hashlib.sha256(payload_b64.encode("ascii") + sec).hexdigest()

# Clean
for i in range(50):
    payload = {"user_id": f"user{i}", "exp": 1800000000 + i, "role": "user"}
    payload_b64 = b64url(json.dumps(payload).encode())
    sig = sign(payload_b64, secret)
    token = f"{payload_b64}.{sig}"
    with open(f"/app/corpus/clean/token_{i}.txt", "w") as f:
        f.write(token)

# Evil
for i in range(50):
    evil_type = i % 4
    if evil_type == 0:
        # Expired
        payload = {"user_id": f"user{i}", "exp": 1700000000, "role": "user"}
        payload_b64 = b64url(json.dumps(payload).encode())
        sig = sign(payload_b64, secret)
    elif evil_type == 1:
        # Forged (modified payload, old sig)
        payload1 = {"user_id": f"user{i}", "exp": 1800000000, "role": "user"}
        sig = sign(b64url(json.dumps(payload1).encode()), secret)
        payload2 = {"user_id": f"user{i}", "exp": 1800000000, "role": "admin"}
        payload_b64 = b64url(json.dumps(payload2).encode())
    elif evil_type == 2:
        # Non-alphanumeric user_id
        payload = {"user_id": f"user{i}\" OR 1=1--", "exp": 1800000000, "role": "user"}
        payload_b64 = b64url(json.dumps(payload).encode())
        sig = sign(payload_b64, secret)
    else:
        # Wrong secret
        payload = {"user_id": f"user{i}", "exp": 1800000000, "role": "user"}
        payload_b64 = b64url(json.dumps(payload).encode())
        sig = sign(payload_b64, b"wrong_secret")

    token = f"{payload_b64}.{sig}"
    with open(f"/app/corpus/evil/token_{i}.txt", "w") as f:
        f.write(token)
'

    # Generate audio
    espeak -w /app/incident_audio.wav "The legacy API uses the HMAC secret key crimson_dynamo_88 for all session tokens."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
