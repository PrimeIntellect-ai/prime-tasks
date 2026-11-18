#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssh-client
pip3 install pytest cryptography flask

useradd -m -s /bin/bash user || true

mkdir -p /home/user/.ssh
chmod 700 /home/user/.ssh
ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
cat /home/user/.ssh/id_rsa.pub > /home/user/.ssh/authorized_keys
chmod 600 /home/user/.ssh/authorized_keys

mkdir -p /home/user/app/uploads

cat << 'EOF' > /home/user/app/app.py
from flask import Flask, request, abort

app = Flask(__name__)

@app.route('/upload', methods=['POST'])
def upload():
    return "File uploaded", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

cat << 'EOF' > /home/user/app/setup_crypto.py
import json
import os
import hashlib
from cryptography.fernet import Fernet

key = Fernet.generate_key()
with open('/home/user/app/old_key.key', 'wb') as f:
    f.write(key)

f = Fernet(key)

files_data = {
    'doc1.txt': b'Confidential HR document 1.',
    'doc2.txt': b'Financial report 2023.',
    'doc3.txt': b'Server passwords and secrets.' # This will be tampered
}

hashes = {}

for filename, content in files_data.items():
    hashes[filename] = hashlib.sha256(content).hexdigest()
    encrypted = f.encrypt(content)
    with open(f'/home/user/app/uploads/{filename}', 'wb') as out:
        out.write(encrypted)

with open('/home/user/app/file_hashes.json', 'w') as out:
    json.dump(hashes, out)

# Tamper with doc3.txt (re-encrypt malicious payload with the old key)
malicious = b'MALICIOUS PAYLOAD'
encrypted_malicious = f.encrypt(malicious)
with open('/home/user/app/uploads/doc3.txt', 'wb') as out:
    out.write(encrypted_malicious)

EOF

python3 /home/user/app/setup_crypto.py
rm /home/user/app/setup_crypto.py

chmod -R 777 /home/user
