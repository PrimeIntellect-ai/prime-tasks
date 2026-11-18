#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 nginx
    pip3 install pytest flask

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create Flask app
    cat << 'EOF' > /app/app.py
import os
import subprocess
import tempfile
from flask import Flask, request

app = Flask(__name__)

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return "No file part", 400
    file = request.files['file']
    if file.filename == '':
        return "No selected file", 400

    fd, temp_path = tempfile.mkstemp(suffix='.csv')
    os.close(fd)
    file.save(temp_path)

    try:
        result = subprocess.run(['bash', '/home/user/validate.sh', temp_path])
        if result.returncode == 0:
            return "Valid", 200
        else:
            return "Invalid", 400
    finally:
        os.remove(temp_path)

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
EOF

    # Create Nginx config (broken proxy_pass)
    cat << 'EOF' > /app/nginx.conf
worker_processes 1;
daemon off;
error_log /dev/stderr;

events {
    worker_connections 1024;
}

http {
    access_log /dev/stdout;
    server {
        listen 8080;
        server_name localhost;

        location /upload {
            proxy_pass http://127.0.0.1:9999;
        }
    }
}
EOF

    # Create clean corpus
    cat << 'EOF' > /app/corpus/clean/clean1.csv
1,A,
2,B,1
3,C,2
EOF

    cat << 'EOF' > /app/corpus/clean/clean2.csv
10,Alice,
20,Bob,10
30,Charlie,10
40,Dave,20
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpus/evil/evil1.csv
1,A,3
2,B,1
3,C,2
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.csv
10,Alice,40
20,Bob,10
30,Charlie,10
40,Dave,20
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
