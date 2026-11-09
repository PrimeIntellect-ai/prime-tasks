#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask werkzeug

    # Create directories
    mkdir -p /home/user/logs
    mkdir -p /home/user/app/uploads

    # Create log file
    cat << 'EOF' > /home/user/logs/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET / HTTP/1.1" 200 2326
198.51.100.42 - - [10/Oct/2023:14:02:11 -0700] "POST /upload HTTP/1.1" 200 42 "filename=../../../../home/user/.bashrc"
10.0.0.5 - - [10/Oct/2023:14:05:01 -0700] "POST /upload HTTP/1.1" 200 42 "filename=legit.txt"
EOF

    # Create server.py
    cat << 'EOF' > /home/user/app/server.py
from flask import Flask, request
import os

app = Flask(__name__)
UPLOAD_DIR = '/home/user/app/uploads/'

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return "No file", 400
    file = request.files['file']
    filename = request.form.get('filename', file.filename)

    # VULNERABLE: No secure_filename used, direct concatenation
    save_path = os.path.join(UPLOAD_DIR, filename)
    file.save(save_path)
    return "Success", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    # Create user and permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
