#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server
    pip3 install pytest

    mkdir -p /app/nginx /app/api /home/user/backups

    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    client_max_body_size 1m; # Agent must change this to 500m
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    cat << 'EOF' > /app/api/requirements.txt
flask==2.3.2
redis==4.5.5
werkzeug==2.3.6
EOF

    cat << 'EOF' > /app/api/app.py
import os
import tarfile
import uuid
from flask import Flask, request

app = Flask(__name__)
BACKUP_DIR = "/home/user/backups"
os.makedirs(BACKUP_DIR, exist_ok=True)

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files.get('file')
    if not file:
        return "No file", 400

    backup_id = str(uuid.uuid4())
    target_dir = os.path.join(BACKUP_DIR, backup_id)
    os.makedirs(target_dir, exist_ok=True)

    # Vulnerable and inefficient extraction
    with tarfile.open(fileobj=file.stream, mode='r|gz') as tar:
        tar.extractall(path=target_dir)

    return "OK", 200

if __name__ == '__main__':
    app.run(port=5000)
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf
cd /app/api && pip install -r requirements.txt
python3 /app/api/app.py &
EOF
    chmod +x /app/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
