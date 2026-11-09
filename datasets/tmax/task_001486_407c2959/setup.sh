#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server curl jq tar
    pip3 install pytest flask redis

    mkdir -p /app
    mkdir -p /home/user/pipeline
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/services/nginx
    mkdir -p /home/user/services/flask
    mkdir -p /home/user/services/redis

    # Nginx config
    cat << 'EOF' > /home/user/services/nginx/nginx.conf
worker_processes 1;
daemon off;
events { worker_connections 1024; }
http {
    access_log /tmp/nginx_access.log;
    error_log /tmp/nginx_error.log;
    client_body_temp_path /tmp/client_body;
    proxy_temp_path /tmp/proxy_temp;
    fastcgi_temp_path /tmp/fastcgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;
    scgi_temp_path /tmp/scgi_temp;
    server {
        listen 8080;
        location /upload {
            proxy_pass http://127.0.0.1:5001;
        }
    }
}
EOF

    # Flask app
    cat << 'EOF' > /home/user/services/flask/app.py
from flask import Flask, request
import tarfile
import redis
import os

app = Flask(__name__)
r = redis.Redis(host='localhost', port=6379, db=0)

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files.get('file')
    if file:
        file.save('/tmp/uploaded.tar.gz')
        # Blindly extracting
        with tarfile.open('/tmp/uploaded.tar.gz') as tar:
            tar.extractall('/tmp/extracted')
        r.set('config_status', 'LOADED')
        return "OK"
    return "No file", 400

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    # Redis config
    cat << 'EOF' > /home/user/services/redis/redis.conf
port 6379
daemonize no
dir /tmp
EOF

    # Startup script
    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server /home/user/services/redis/redis.conf &
python3 /home/user/services/flask/app.py &
nginx -c /home/user/services/nginx/nginx.conf &
sleep 2
EOF
    chmod +x /app/start_services.sh

    # Create dummy corpora
    mkdir -p /tmp/corpus_clean /tmp/corpus_evil
    echo '{"service": "web", "workers": 4}' > /tmp/corpus_clean/app_config.json
    tar -czf /home/user/corpora/clean/test1.tar.gz -C /tmp/corpus_clean app_config.json
    tar -czf /home/user/corpora/clean/verify.tar.gz -C /tmp/corpus_clean app_config.json

    echo "bad" > /tmp/corpus_evil/bad.sh
    tar -czf /home/user/corpora/evil/bad1.tar.gz -C /tmp/corpus_evil bad.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
