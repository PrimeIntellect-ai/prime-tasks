#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest setuptools

    # Create user
    useradd -m -s /bin/bash user || true

    # Create directories
    mkdir -p /app/file_vault/file_vault
    mkdir -p /app/uploads
    mkdir -p /home/user/evidence

    # Create setup.py with deliberate typo ('flsk')
    cat << 'EOF' > /app/file_vault/setup.py
from setuptools import setup, find_packages

setup(
    name='file_vault',
    version='1.0.0',
    packages=find_packages(),
    install_requires=[
        'flsk',
        'werkzeug'
    ],
)
EOF

    # Create __init__.py
    touch /app/file_vault/file_vault/__init__.py

    # Create vulnerable server.py
    cat << 'EOF' > /app/file_vault/file_vault/server.py
from flask import Flask, request
import os

app = Flask(__name__)
UPLOAD_DIR = '/app/uploads'

if not os.path.exists(UPLOAD_DIR):
    os.makedirs(UPLOAD_DIR)

@app.route('/upload', methods=['POST'])
def upload_file():
    # Broken token validation logic
    auth_header = request.headers.get('Authorization')
    # TODO: Implement proper token validation here
    # if not auth_header or auth_header != "Bearer <token>":
    #     return "Unauthorized", 401

    if 'file' not in request.files:
        return "No file part", 400

    file = request.files['file']
    if file.filename == '':
        return "No selected file", 400

    # Vulnerable to path traversal
    filename = file.filename
    save_path = os.path.join(UPLOAD_DIR, filename)

    try:
        file.save(save_path)
        return "File uploaded successfully", 200
    except Exception as e:
        return str(e), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=9090)
EOF

    # Create evidence files
    cat << 'EOF' > /home/user/evidence/token.hex
71717150524673434f4b4c7f563249514c
EOF

    cat << 'EOF' > /home/user/evidence/encryptor.py
def encrypt(text, key=0x42):
    return bytes([ord(c) ^ key for c in text]).hex()
EOF

    # Set permissions
    chmod -R 777 /app
    chmod -R 777 /home/user
