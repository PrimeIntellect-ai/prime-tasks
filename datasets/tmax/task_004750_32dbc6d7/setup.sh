#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server openssh-server
    pip3 install pytest flask redis gunicorn

    mkdir -p /app

    cat << 'EOF' > /app/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    cat << 'EOF' > /app/api.py
from flask import Flask
import os
import secrets

app = Flask(__name__)

@app.route('/generate_task', methods=['POST'])
def generate_task():
    tok = "SEC-" + secrets.token_hex(16)
    os.system(f"python3 /app/worker.py --token {tok} &")
    return "Task spawned", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/worker.py
import argparse
import time

parser = argparse.ArgumentParser()
parser.add_argument('--token', required=True)
args = parser.parse_args()

print(f"Working on {args.token}")
time.sleep(1)
EOF

    cat << 'EOF' > /app/sshd_config
Port 2222
PasswordAuthentication yes
AuthorizedKeysFile /home/user/.ssh/authorized_keys
HostKey /etc/ssh/ssh_host_rsa_key
EOF

    cat << 'EOF' > /app/token_validator.py
def is_valid_token(token_string):
    if not token_string.startswith("SEC-"):
        return False
    return "VALID" in token_string
EOF

    cat << 'EOF' > /app/generate_logs.py
import random
valid_tokens = [f"SEC-VALID{i:04d}" for i in range(500)]
invalid_tokens = [f"SEC-INVALID{i:04d}" for i in range(200)]
all_tokens = valid_tokens + invalid_tokens

with open('/app/.hidden_truth.txt', 'w') as f:
    for t in valid_tokens:
        f.write(t + '\n')

with open('/app/historical_syslogs.txt', 'w') as f:
    for i in range(10000):
        if i < 700:
            f.write(f"execve worker.py --token {all_tokens[i]}\n")
        else:
            f.write("execve something_else\n")
EOF

    python3 /app/generate_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
