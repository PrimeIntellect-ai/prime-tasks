#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest flask requests

    # Create directories
    mkdir -p /home/user/app/uploads
    mkdir -p /home/user/logs

    # Create the vulnerable Flask app
    cat << 'EOF' > /home/user/app/server.py
from flask import Flask, request
import os

app = Flask(__name__)
UPLOAD_DIR = "/home/user/app/uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return "No file part", 400
    file = request.files['file']
    if file.filename == '':
        return "No selected file", 400

    # VULNERABILITY: Path Traversal
    save_path = os.path.join(UPLOAD_DIR, file.filename)
    try:
        file.save(save_path)
        return "File uploaded successfully", 200
    except Exception as e:
        return str(e), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create the log file showing the attack
    cat << 'EOF' > /home/user/logs/access.log
127.0.0.1 - - [14/Nov/2023 09:12:34] "GET / HTTP/1.1" 404 -
127.0.0.1 - - [14/Nov/2023 09:15:22] "POST /upload HTTP/1.1" 200 - filename="../../system_cache.bin"
EOF

    # Generate the XOR encrypted payload
    python3 -c '
def xor_crypt(data, key):
    return bytes([b ^ key[i % len(key)] for i, b in enumerate(data)])
plain = b"import os\n# Attacker backdoor\nprint(\"FLAG{tr4v3rs4l_m4lw4r3_f0und}\")\n"
key = b"irks"
cipher = xor_crypt(plain, key)
with open("/home/user/system_cache.bin", "wb") as f:
    f.write(cipher)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
