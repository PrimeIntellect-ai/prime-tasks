#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        nginx \
        redis-server \
        gcc \
        file \
        binutils \
        curl \
        procps

    pip3 install pytest flask redis python-dotenv

    mkdir -p /app
    mkdir -p /home/user/artifacts/backlog
    mkdir -p /home/user/artifacts/final

    # Create Nginx config with wrong upstream port
    cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5001;
        }
    }
}
EOF

    # Create .env with wrong Redis port
    cat << 'EOF' > /app/.env
REDIS_HOST=127.0.0.1
REDIS_PORT=6380
EOF

    # Create Flask app
    cat << 'EOF' > /app/app.py
import os
import redis
from flask import Flask, request
from dotenv import load_dotenv

load_dotenv('/app/.env')

app = Flask(__name__)
r = redis.Redis(host=os.getenv('REDIS_HOST', '127.0.0.1'), port=int(os.getenv('REDIS_PORT', 6379)))

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return "No file", 400
    file = request.files['file']
    file_data = file.read()
    filename = file.filename
    r.lpush('artifact_queue', f"{filename}::{file_data.hex()}")
    return "Uploaded", 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create worker
    cat << 'EOF' > /app/worker.py
import os
import redis
import time
from dotenv import load_dotenv

load_dotenv('/app/.env')

r = redis.Redis(host=os.getenv('REDIS_HOST', '127.0.0.1'), port=int(os.getenv('REDIS_PORT', 6379)))
final_dir = '/home/user/artifacts/final'
os.makedirs(final_dir, exist_ok=True)

while True:
    try:
        item = r.brpop('artifact_queue', timeout=1)
        if item:
            _, data = item
            data = data.decode('utf-8')
            filename, hex_data = data.split('::', 1)
            file_data = bytes.fromhex(hex_data)
            with open(os.path.join(final_dir, filename), 'wb') as f:
                f.write(file_data)
    except Exception as e:
        pass
    time.sleep(0.1)
EOF

    # Create restart script
    cat << 'EOF' > /app/restart_services.sh
#!/bin/bash
pkill -f nginx || true
pkill -f app.py || true
pkill -f worker.py || true
pkill -f redis-server || true

redis-server --daemonize yes
nginx -c /app/nginx.conf
nohup python3 /app/app.py > /app/flask.log 2>&1 &
nohup python3 /app/worker.py > /app/worker.log 2>&1 &
EOF
    chmod +x /app/restart_services.sh

    # Generate 50 ELF binaries with debug symbols
    cat << 'EOF' > /tmp/dummy.c
#include <stdio.h>
int main() {
    printf("Hello World\n");
    return 0;
}
EOF

    for i in $(seq 1 50); do
        gcc -g /tmp/dummy.c -o "/home/user/artifacts/backlog/binary_$i"
    done
    rm /tmp/dummy.c

    useradd -m -s /bin/bash user || true
    chown -R user:user /app /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
