#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python2 curl redis-server nginx
    pip3 install pytest flask redis requests

    # Install pip for Python 2 and Flask
    curl -sSL https://bootstrap.pypa.io/pip/2.7/get-pip.py -o get-pip.py
    python2 get-pip.py
    pip2 install flask

    mkdir -p /home/user/app/legacy
    mkdir -p /home/user/app/v2

    cat << 'EOF' > /home/user/app/legacy/app.py
from flask import Flask, request, jsonify
import hashlib
import time

app = Flask(__name__)

def heavy_checksum(payload):
    # Simulate a heavy error-correcting cryptographic checksum
    time.sleep(0.05) 
    return hashlib.sha256(payload.encode('utf-8')).hexdigest()

@app.route('/verify', methods=['GET'])
def verify():
    payload = request.args.get('payload', '')
    sig = request.args.get('sig', '')
    expected = heavy_checksum(payload)
    return jsonify({"valid": expected == sig})

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
