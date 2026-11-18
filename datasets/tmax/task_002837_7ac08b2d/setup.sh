#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest flask

    mkdir -p /home/user/forensics/proc_dump/1337
    mkdir -p /home/user/app
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Create proc_dump with secret key
    printf "python3\0worker.py\0--secret-key=cRyPt0_k3y_99\0" > /home/user/forensics/proc_dump/1337/cmdline

    # Generate tokens using Python
    cat << 'EOF' > /tmp/gen_tokens.py
import base64

key = "cRyPt0_k3y_99"

def encode_token(text):
    xored = bytes([ord(c) ^ ord(key[i % len(key)]) for i, c in enumerate(text)])
    return base64.b64encode(xored).decode('utf-8')

clean_json = '{"user": "alice", "role": "user", "exp": 1999999999}'
evil_json = '{"user": "hacker", "role": "admin", "exp": 1999999999}'

with open('/home/user/corpus/clean/tokens.txt', 'w') as f:
    f.write(encode_token(clean_json) + '\n')

with open('/home/user/corpus/evil/tokens.txt', 'w') as f:
    f.write(encode_token(evil_json) + '\n')
EOF
    python3 /tmp/gen_tokens.py
    rm /tmp/gen_tokens.py

    # Create Flask backend
    cat << 'EOF' > /home/user/app/backend.py
from flask import Flask
app = Flask(__name__)

@app.route('/api/data')
def data():
    return "Hello", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create Nginx config
    cat << 'EOF' > /home/user/app/nginx.conf
worker_processes 1;
daemon off;
events {
    worker_connections 1024;
}
http {
    server {
        listen 8000;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
