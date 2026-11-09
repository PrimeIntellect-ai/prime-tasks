#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import base64

key = "COMPLIANCE"

def encrypt(text):
    encrypted = bytearray()
    for i, char in enumerate(text):
        encrypted.append(ord(char) ^ ord(key[i % len(key)]))
    return base64.b64encode(encrypted).decode('utf-8')

urls = [
    "/dashboard",
    "https://evil.com/login",
    "/settings",
    "http://phishing.org/auth",
    "/profile?id=123",
    "https://attacker.net/steal?cookie=1"
]

log_entries = [
    f'192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /login?token={encrypt(urls[0])} HTTP/1.1" 200 -',
    f'192.168.1.11 - - [10/Oct/2023:13:56:10 -0700] "GET /login?token={encrypt(urls[1])} HTTP/1.1" 302 -',
    f'192.168.1.12 - - [10/Oct/2023:13:58:20 -0700] "GET /login?token={encrypt(urls[2])} HTTP/1.1" 200 -',
    f'192.168.1.13 - - [10/Oct/2023:13:59:01 -0700] "GET /login?token={encrypt(urls[3])} HTTP/1.1" 302 -',
    f'192.168.1.14 - - [10/Oct/2023:14:01:15 -0700] "GET /login?token={encrypt(urls[4])} HTTP/1.1" 200 -',
    f'192.168.1.15 - - [10/Oct/2023:14:05:30 -0700] "GET /login?token={encrypt(urls[5])} HTTP/1.1" 302 -'
]

with open("/home/user/access.log", "w") as f:
    for entry in log_entries:
        f.write(entry + "\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
