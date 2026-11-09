#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    echo -n "compliance_audit_key_992" > /home/user/secret.key

    cat << 'EOF' > /tmp/setup.py
import hmac
import hashlib
import base64

key = b"compliance_audit_key_992"

def make_mac(b64_payload):
    h = hmac.new(key, b64_payload.encode(), hashlib.sha256).digest()
    return base64.urlsafe_b64encode(h).decode().rstrip("=")

p1 = base64.urlsafe_b64encode(b'{"user": "mallory"}').decode().rstrip("=")
mac1 = make_mac(p1)

lines = [
    "eyJ1c2VyIjogImJvYiJ9.4V_zL9f4b-Jb8eGk-7_d1U3JgQ_q8W1M_5tL-r_Qcxg | cmVwb3J0LnBkZg==",
    f"{p1}.{mac1} | Li4vLi4vLi4vZXRjL3Bhc3N3ZA==",
    "eyJ1c2VyIjogImV2ZSJ9.aW52YWxpZF9tYWNfc3RyaW5n | aW1hZ2VzLy4uJTJmLi4lMmZjb25maWcueW1s",
    "eyJ1c2VyIjogImFsaWNlIn0.validity_not_checked_because_benign | c2FmZV9maWxlLnR4dA==",
    "eyJ1c2VyIjogImNoYXJsaWUifQ.KjKqN3M2kI3Q8QcR0V9_M4zS6D1Y5L-vG_uW_E8x_p_ | YXBwL2xvZ3MvLi4vLi4vYmFja3Vwcy9kYi5zcWw="
]

with open('/home/user/upload_logs.txt', 'w') as f:
    for line in lines:
        f.write(line + '\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
