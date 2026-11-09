#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/incident_014
cd /home/user/incident_014

cat << 'EOF' > auth_module.py
import base64
import json
import hmac
import hashlib

SECRET = "S3cr3tK3y1337!"

def verify_token(token):
    try:
        parts = token.split('.')
        if len(parts) != 3:
            return None
        header_b64, payload_b64, signature_b64 = parts

        # Add padding back for decoding
        header_json = base64.urlsafe_b64decode(header_b64 + '====').decode('utf-8')
        payload_json = base64.urlsafe_b64decode(payload_b64 + '====').decode('utf-8')

        header = json.loads(header_json)
        payload = json.loads(payload_json)

        # VULNERABILITY: algorithm=none bypasses signature check
        if header.get("alg", "").lower() == "none":
            return payload.get("user")

        # Standard check
        msg = (header_b64 + '.' + payload_b64).encode('utf-8')
        expected_sig = hmac.new(SECRET.encode('utf-8'), msg, hashlib.sha256).digest()
        expected_sig_b64 = base64.urlsafe_b64encode(expected_sig).decode('utf-8').rstrip('=')

        if signature_b64 == expected_sig_b64:
            return payload.get("user")
        return None
    except Exception as e:
        return None
EOF

python3 -m py_compile auth_module.py
mv __pycache__/auth_module.*.pyc auth_module.pyc
rm -rf __pycache__ auth_module.py

cat << 'EOF' > generate_logs.py
import base64
import json
import hmac
import hashlib

SECRET = "S3cr3tK3y1337!"

def create_valid_token(user):
    header = base64.urlsafe_b64encode(json.dumps({"alg": "HS256"}).encode()).decode().rstrip('=')
    payload = base64.urlsafe_b64encode(json.dumps({"user": user}).encode()).decode().rstrip('=')
    msg = (header + '.' + payload).encode()
    sig = hmac.new(SECRET.encode(), msg, hashlib.sha256).digest()
    sig_b64 = base64.urlsafe_b64encode(sig).decode().rstrip('=')
    return f"{header}.{payload}.{sig_b64}"

def create_exploit_token(user):
    header = base64.urlsafe_b64encode(json.dumps({"alg": "none"}).encode()).decode().rstrip('=')
    payload = base64.urlsafe_b64encode(json.dumps({"user": user}).encode()).decode().rstrip('=')
    return f"{header}.{payload}." # empty signature

logs = [
    f"[2023-10-24 10:01:22] IP=10.0.0.5 User=alice Status=Success Token={create_valid_token('alice')}",
    f"[2023-10-24 10:05:11] IP=10.0.0.8 User=admin Status=Success Token={create_valid_token('admin')}", # Valid admin login
    f"[2023-10-24 10:15:33] IP=192.168.1.104 User=admin Status=Success Token={create_exploit_token('admin')}", # EXPLOIT 1
    f"[2023-10-24 10:22:45] IP=10.0.0.9 User=bob Status=Failed Token={create_valid_token('bob')[:-2]}AA",
    f"[2023-10-24 10:31:12] IP=203.0.113.42 User=admin Status=Success Token={create_exploit_token('admin')}", # EXPLOIT 2
    f"[2023-10-24 10:35:01] IP=10.0.0.8 User=admin Status=Success Token={create_valid_token('admin')}", # Valid admin login
    f"[2023-10-24 10:45:55] IP=192.168.1.104 User=admin Status=Success Token={create_exploit_token('admin')}", # EXPLOIT 1 (duplicate IP)
]

with open("auth.log", "w") as f:
    for log in logs:
        f.write(log + "\n")
EOF

python3 generate_logs.py
rm generate_logs.py

chown -R user:user /home/user/incident_014
chmod -R 777 /home/user
