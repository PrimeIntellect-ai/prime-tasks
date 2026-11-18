#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libssl-dev build-essential
    pip3 install pytest pycryptodome

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_setup.py
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad
import base64

key = b'0123456789abcdef'
iv = b'abcdef9876543210'
token1 = b'super_secret_admin_token_2023'
token2 = b'invalid_token_guess_1'
token3 = b'<script>alert("xss")</script>'

def encrypt_token(t):
    cipher = AES.new(key, AES.MODE_CBC, iv)
    enc = cipher.encrypt(pad(t, AES.block_size))
    return base64.b64encode(enc).decode('utf-8')

with open('/home/user/key.txt', 'w') as f:
    f.write(key.decode('utf-8'))

with open('/home/user/iv.txt', 'w') as f:
    f.write(iv.decode('utf-8'))

log_content = f"""192.168.1.5 - - [10/Oct/2023:13:55:00 -0700] "GET /api/admin?token={encrypt_token(token2)} HTTP/1.1" 403 2326
192.168.1.8 - - [10/Oct/2023:13:56:12 -0700] "GET /api/admin?token={encrypt_token(token3)} HTTP/1.1" 400 512
10.0.0.45 - - [10/Oct/2023:13:58:30 -0700] "GET /api/admin?token={encrypt_token(token1)} HTTP/1.1" 200 1024
192.168.1.9 - - [10/Oct/2023:13:59:01 -0700] "POST /api/login HTTP/1.1" 401 200
"""

with open('/home/user/access.log', 'w') as f:
    f.write(log_content)
EOF

    python3 /home/user/generate_setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
