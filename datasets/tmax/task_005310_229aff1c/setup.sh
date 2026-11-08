#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx
    pip3 install pytest flask gunicorn werkzeug

    mkdir -p /app/backend /app/proxy /app/uploads /app/logs

    cat << 'EOF' > /app/backend/app.py
import os
from flask import Flask, request, make_response

app = Flask(__name__)
UPLOAD_FOLDER = '/app/uploads/'

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return 'No file part', 400
    file = request.files['file']
    if file.filename == '':
        return 'No selected file', 400

    # Vulnerable path traversal
    filename = file.filename
    save_path = os.path.join(UPLOAD_FOLDER, filename)
    file.save(save_path)
    return 'File uploaded successfully', 200

@app.route('/login', methods=['GET'])
def login():
    resp = make_response("Logged in")
    resp.set_cookie('session_id', '123456789')
    return resp

@app.route('/', methods=['GET'])
def index():
    return 'Hello World', 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    cat << 'EOF' > /app/proxy/nginx.conf
worker_processes 1;
daemon off;
error_log /app/logs/error.log;
pid /app/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /app/logs/access.log;
    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://127.0.0.1:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

    cat << 'EOF' > /app/logs/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET / HTTP/1.1" 200 2326
192.168.1.55 - - [10/Oct/2023:13:56:10 -0700] "GET /images/../../../etc/passwd HTTP/1.1" 404 123
10.0.0.42 - - [10/Oct/2023:13:57:02 -0700] "GET /download?file=%2e%2e%2f%2e%2e%2fetc%2fshadow HTTP/1.1" 400 32
192.168.1.20 - - [10/Oct/2023:13:58:11 -0700] "POST /upload HTTP/1.1" 200 45
172.16.0.100 - - [10/Oct/2023:13:59:45 -0700] "GET /api/v1/resource?path=..%2F..%2F..%2Fetc%2Fpasswd HTTP/1.1" 403 99
192.168.1.15 - - [10/Oct/2023:14:00:00 -0700] "GET /login HTTP/1.1" 200 45
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
cd /app/backend
gunicorn -b 127.0.0.1:5000 app:app &
nginx -c /app/proxy/nginx.conf &
wait
EOF

    chmod +x /app/start_services.sh
    chmod -R 777 /app/uploads
    chmod -R 777 /app/logs
    chmod -R 777 /app/proxy

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
