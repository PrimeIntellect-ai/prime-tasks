#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip procps
pip3 install pytest flask requests

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/vuln_server.py
from flask import Flask, request
import os

app = Flask(__name__)
UPLOAD_DIR = "/tmp/uploads/"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return "No file part", 400
    file = request.files['file']
    if file.filename == '':
        return "No selected file", 400

    content = file.read()
    if not content.startswith(b'\x7fELF'):
        return "Invalid file type. Only ELF binaries allowed.", 403

    target_path = os.path.abspath(UPLOAD_DIR + file.filename)

    try:
        with open(target_path, 'wb') as f:
            f.write(content)
        return "File uploaded successfully", 200
    except Exception as e:
        return str(e), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=9090)
EOF

echo 'if ! pgrep -f vuln_server.py > /dev/null; then nohup python3 /tmp/vuln_server.py > /tmp/server.log 2>&1 & sleep 1; fi' >> /etc/bash.bashrc
echo 'if ! pgrep -f vuln_server.py > /dev/null; then nohup python3 /tmp/vuln_server.py > /tmp/server.log 2>&1 & sleep 1; fi' >> /home/user/.bashrc

chmod -R 777 /home/user
