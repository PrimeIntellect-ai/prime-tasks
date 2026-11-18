#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl
    pip3 install pytest flask redis gunicorn

    mkdir -p /app/nginx
    mkdir -p /app/tests/corpus/clean
    mkdir -p /app/tests/corpus/evil
    mkdir -p /app/uploads

    cat << 'EOF' > /app/nginx/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    client_max_body_size 1m;
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:5000;
        }
    }
}
EOF

    cat << 'EOF' > /app/app.py
from flask import Flask, request
import redis
import os

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return "No file part", 400
    file = request.files['file']
    if file.filename == '':
        return "No selected file", 400
    filepath = os.path.join('/app/uploads', file.filename)
    file.save(filepath)
    r.lpush('csv_queue', filepath)
    return "OK", 200
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /app/nginx/nginx.conf
gunicorn --bind 127.0.0.1:5000 --chdir /app app:app --daemon
EOF
    chmod +x /app/start_services.sh

    cat << 'EOF' > /app/tests/corpus/clean/clean1.csv
user_id,timestamp,transaction_amount,other
1,2023-01-01T00:00:00Z,100.0,foo
2,2023-01-01T00:01:00Z,200.0,bar
EOF

    cat << 'EOF' > /app/tests/corpus/clean/clean2.csv
user_id,timestamp,transaction_amount,other
3,2023-01-01T00:02:00Z,300.0,"Address
Line 2"
EOF

    cat << 'EOF' > /app/tests/corpus/evil/evil1.csv
user_id,timestamp,transaction_amount,other
4,2023-01-01T00:03:00Z,400.0,"=cmd|' /C calc'!A0"
EOF

    cat << 'EOF' > /app/tests/corpus/evil/evil2.csv
user_id,timestamp,transaction_amount,other
5,2023-01-01T00:04:00Z,500.0,"-2+3+cmd"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
