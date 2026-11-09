#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest cryptography

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import json
import hashlib
from cryptography.fernet import Fernet

os.makedirs("/home/user", exist_ok=True)

key = Fernet.generate_key()
with open("/home/user/auth_key.key", "wb") as kf:
    kf.write(key)

endpoint = "/api/v3/hidden_command_c2_991x"
chk = hashlib.sha256(endpoint.encode()).hexdigest()
payload = json.dumps({
    "user": "system_admin",
    "role": "engineer",
    "next_endpoint": endpoint,
    "checksum": chk
})

f = Fernet(key)
token = f.encrypt(payload.encode())

with open("/home/user/intercepted_token.txt", "wb") as tf:
    tf.write(token)
'

    chmod -R 777 /home/user
    chmod 777 /home/user/auth_key.key
