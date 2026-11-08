#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev make curl
    pip3 install pytest flask requests pycryptodome

    mkdir -p /app

    cat << 'EOF' > /app/backend.py
from flask import Flask
app = Flask(__name__)

@app.route('/', defaults={'path': ''}, methods=['GET', 'POST', 'PUT', 'DELETE'])
@app.route('/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE'])
def catch_all(path):
    return "OK", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8081)
EOF

    cat << 'EOF' > /app/verifier.py
import requests
import time
import os
import binascii
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad

# This is a dummy verifier for initial state.
print("METRIC_ACCURACY_SCORE: 1.0")
EOF

    chmod +x /app/backend.py /app/verifier.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
