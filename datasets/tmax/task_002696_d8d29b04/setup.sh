#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/captures

    python3 -c '
import os

key = b"\xde\xad\xbe\xef"

def encrypt(plaintext):
    return bytes([plaintext[i] ^ key[i % 4] for i in range(len(plaintext))])

files = {
    "admin_login.bin": b"{\"user\":\"admin\",\"role\":\"administrator\"}",
    "user_1.bin": b"{\"user\":\"alice\",\"role\":\"user\"}",
    "user_2.bin": b"{\"user\":\"bob\",\"role\":\"user\"}",
    "service_77.bin": b"{\"user\":\"svc_account\",\"role\":\"system_backup\"}"
}

for filename, plaintext in files.items():
    with open(f"/home/user/captures/{filename}", "wb") as f:
        f.write(encrypt(plaintext))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
