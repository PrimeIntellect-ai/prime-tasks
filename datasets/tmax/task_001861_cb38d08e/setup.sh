#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/generate_artifacts.py
import dis
import sys
import hashlib
import base64

def generate_token(user, csp):
    secret = "S3cr3t_P0licy_K3y_2024!"
    data = secret + user + csp
    sig = hashlib.sha256(data.encode('utf-8')).hexdigest()
    u_b64 = base64.b64encode(user.encode('utf-8')).decode('utf-8')
    c_b64 = base64.b64encode(csp.encode('utf-8')).decode('utf-8')
    return u_b64 + "." + c_b64 + "." + sig

# Write disassembly to file
with open('/home/user/app/token_signer.dis', 'w') as f:
    sys.stdout = f
    dis.dis(generate_token)
    sys.stdout = sys.__stdout__

# Generate sample token
sample_user = "dev-test"
sample_csp = "default-src 'self'; script-src 'self' 'unsafe-inline';"
token = generate_token(sample_user, sample_csp)
with open('/home/user/app/sample_token.txt', 'w') as f:
    f.write(token)
EOF

    python3 /home/user/app/generate_artifacts.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
