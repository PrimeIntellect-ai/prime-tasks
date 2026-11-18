#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick curl nginx

    # Install Node.js
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    # Install Python packages
    pip3 install --default-timeout=100 pytest flask gunicorn

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create architecture image
    mkdir -p /app
    convert -size 800x400 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 50,100 'Nginx Port 8080. Route /python -> unix:/home/user/run/python.sock. Route /node -> 127.0.0.1:8081'" /app/architecture.png

    # Setup Python API
    mkdir -p /home/user/python_api
    cat << 'EOF' > /home/user/python_api/app.py
from flask import Flask
app = Flask(__name__)
@app.route('/python')
def hello():
    return "Hello from Python", 200
EOF

    # Setup Node.js API
    mkdir -p /home/user/node_api
    cat << 'EOF' > /home/user/node_api/app.js
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;
app.get('/node', (req, res) => res.status(200).send('Hello from Node'));
app.listen(port, () => console.log(`Node running on ${port}`));
EOF
    cd /home/user/node_api && npm install express

    # Setup Nginx config
    mkdir -p /home/user/nginx
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log /home/user/nginx/error.log;
pid /home/user/nginx/nginx.pid;
events { worker_connections 1024; }
http {
    access_log /home/user/nginx/access.log;
    server {
        listen 8080;
        server_name 127.0.0.1;
        location /python {
            proxy_pass http://unix:/var/run/wrong.sock;
        }
        location /node {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    # Setup benchmark script
    cat << 'EOF' > /home/user/bench.py
import urllib.request
import time

def run():
    success = 0
    total = 100
    for _ in range(total):
        try:
            r1 = urllib.request.urlopen('http://127.0.0.1:8080/python', timeout=1)
            r2 = urllib.request.urlopen('http://127.0.0.1:8080/node', timeout=1)
            if r1.getcode() == 200 and r2.getcode() == 200:
                success += 1
        except Exception:
            pass
        time.sleep(0.01)
    print(success / total)

if __name__ == '__main__':
    run()
EOF

    chmod -R 777 /home/user
