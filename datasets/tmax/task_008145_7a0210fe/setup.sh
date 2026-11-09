#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/run

    cat << 'EOF' > /home/user/app/nginx.conf
server {
    listen 8080;
    server_name localhost;

    location / {
        proxy_pass http://unix:/home/user/run/old_app.sock;
        proxy_set_header Host $host;
    }
}
EOF

    cat << 'EOF' > /home/user/app/backend.env
APP_ENV=production
LISTEN_SOCKET=/home/user/run/production_backend.sock
LOG_LEVEL=info
EOF

    touch /home/user/run/production_backend.sock

    chmod -R 777 /home/user
