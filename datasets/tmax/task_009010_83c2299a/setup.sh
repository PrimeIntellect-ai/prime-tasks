#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx socat curl procps cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backend/logs
    mkdir -p /home/user/nginx/logs

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log /home/user/nginx/logs/error.log;
pid /home/user/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/nginx/logs/access.log;
    server {
        listen 127.0.0.1:8080;
        location /api {
            proxy_pass http://127.0.0.1:8081;
        }
    }
}
EOF

    # Create an environment script to start socat and set permissions dynamically
    # This ensures the backend is running when tests or the agent interact with the container
    cat << 'EOF' > /.singularity.d/env/99-socat.sh
if ! pgrep -f "socat UNIX-LISTEN:/home/user/backend/app.sock" > /dev/null; then
    chmod 755 /home/user/backend 2>/dev/null || true
    nohup socat UNIX-LISTEN:/home/user/backend/app.sock,fork,reuseaddr SYSTEM:'echo -e "HTTP/1.1 200 OK\r\nContent-Length: 21\r\n\r\nBACKEND_SUCCESS_77812"' > /dev/null 2>&1 &
    sleep 0.5
    chmod 000 /home/user/backend 2>/dev/null || true
fi
EOF
    chmod +x /.singularity.d/env/99-socat.sh

    chmod -R 777 /home/user
    chmod 000 /home/user/backend
