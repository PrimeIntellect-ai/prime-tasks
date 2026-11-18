#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest cryptography

    mkdir -p /home/user

    cat <<'EOF' > /tmp/setup.py
import os
import json
import binascii
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

os.makedirs("/home/user", exist_ok=True)

key_hex = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
key_bytes = binascii.unhexlify(key_hex)
aesgcm = AESGCM(key_bytes)

with open("/home/user/key.txt", "w") as f:
    f.write(key_hex)

payloads = [
    {
        "ip": "192.168.1.55",
        "raw": 'POST /upload HTTP/1.1\r\nHost: internal.corp\r\nContent-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW\r\n\r\n------WebKitFormBoundary7MA4YWxkTrZu0gW\r\nContent-Disposition: form-data; name="file"; filename="report.pdf"\r\n\r\n%PDF-1.4...\r\n------WebKitFormBoundary7MA4YWxkTrZu0gW--'
    },
    {
        "ip": "10.5.22.114",
        "raw": 'POST /upload HTTP/1.1\r\nHost: internal.corp\r\nContent-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW\r\n\r\n------WebKitFormBoundary7MA4YWxkTrZu0gW\r\nContent-Disposition: form-data; name="file"; filename="../../../../etc/shadow"\r\n\r\nmalicious_content_here\r\n------WebKitFormBoundary7MA4YWxkTrZu0gW--'
    },
    {
        "ip": "172.16.0.12",
        "raw": 'POST /upload HTTP/1.1\r\nHost: internal.corp\r\nContent-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW\r\n\r\n------WebKitFormBoundary7MA4YWxkTrZu0gW\r\nContent-Disposition: form-data; name="file"; filename="image.png"\r\n\r\nPNG_DATA\r\n------WebKitFormBoundary7MA4YWxkTrZu0gW--'
    }
]

traffic_log = []
nonce_counter = 1
for p in payloads:
    # 12-byte nonce
    nonce = nonce_counter.to_bytes(12, byteorder='big')
    nonce_counter += 1

    ct = aesgcm.encrypt(nonce, p["raw"].encode('utf-8'), None)
    # The ciphertext stored is nonce + actual ciphertext
    full_ct = nonce + ct

    traffic_log.append({
        "ip": p["ip"],
        "ciphertext": binascii.hexlify(full_ct).decode('utf-8')
    })

with open("/home/user/traffic.json", "w") as f:
    for entry in traffic_log:
        f.write(json.dumps(entry) + "\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
