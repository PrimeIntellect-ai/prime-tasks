#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask requests

    mkdir -p /home/user/workspace/api/utils
    mkdir -p /home/user/workspace/data

    touch /home/user/workspace/data/config.json
    echo "Error: connection timeout" > /home/user/workspace/data/app.log

    cat << 'EOF' > /home/user/workspace/api/app.py
from flask import Flask, request, jsonify
# BROKEN IMPORT:
from hashing import verify_checksums

app = Flask(__name__)

@app.route('/verify_files', methods=['POST'])
def verify():
    data = request.get_json()
    failed = verify_checksums(data.get('constraints', []))
    return jsonify({"failed_files": failed})

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /home/user/workspace/api/utils/hashing.py
import hashlib
import os

DATA_DIR = "/home/user/workspace/data"

def verify_checksums(constraints):
    # TODO: Implement checksum verification
    pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
