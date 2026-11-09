#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git nginx curl psmisc
    pip3 install pytest Flask==2.2.2 gunicorn==20.1.0 Werkzeug==2.2.2

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config
    mkdir -p /home/user/logs
    mkdir -p /home/user/run
    mkdir -p /home/user/deploy_target

    git config --global init.defaultBranch master
    git config --global user.email "user@example.com"
    git config --global user.name "User"

    git init --bare /home/user/staging.git

    cat << 'EOF' > /home/user/staging.git/hooks/post-receive
#!/bin/bash

echo "Starting deployment..."
git --work-tree=/home/user/deploy_target --git-dir=/home/user/staging.git checkout -f

# Stop previous instances if running
pkill -f gunicorn || true
nginx -c /home/user/config/nginx.conf -s stop || true
sleep 1

cd /home/user/deploy_target

# ISSUE: Missing timezone and locale environment variables here
gunicorn --bind unix:/home/user/run/app.sock app:app --daemon

# Start Nginx
nginx -c /home/user/config/nginx.conf

echo "Waiting for services to boot..."
sleep 2

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/health)
if [ "$HTTP_STATUS" != "200" ]; then
    echo "Health check failed with status $HTTP_STATUS"
    exit 1
fi
echo "Deployment successful!"
EOF
    chmod +x /home/user/staging.git/hooks/post-receive

    cat << 'EOF' > /home/user/config/nginx.conf
worker_processes 1;
error_log /home/user/logs/error.log;
pid /home/user/run/nginx.pid;
events { worker_connections 1024; }
http {
    access_log /home/user/logs/access.log;
    client_body_temp_path /home/user/run/client_body;
    proxy_temp_path /home/user/run/proxy_temp;
    fastcgi_temp_path /home/user/run/fastcgi_temp;
    uwsgi_temp_path /home/user/run/uwsgi_temp;
    scgi_temp_path /home/user/run/scgi_temp;

    upstream backend {
        server unix:/home/user/run/wrong_app.sock;
    }

    server {
        listen 8080;
        location / {
            proxy_pass http://backend;
            proxy_set_header Host $host;
        }
    }
}
EOF

    git clone /home/user/staging.git /home/user/workspace
    cd /home/user/workspace
    cat << 'EOF' > app.py
import os
from flask import Flask, jsonify

if os.environ.get('TZ') != 'UTC' or os.environ.get('LANG') != 'en_US.UTF-8':
    raise RuntimeError("Invalid locale or timezone configuration")

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "ok"})
EOF
    cat << 'EOF' > requirements.txt
Flask==2.2.2
gunicorn==20.1.0
EOF
    git add app.py requirements.txt
    git commit -m "Initial commit"
    git push origin master || true

    chown -R user:user /home/user
    chmod -R 777 /home/user
