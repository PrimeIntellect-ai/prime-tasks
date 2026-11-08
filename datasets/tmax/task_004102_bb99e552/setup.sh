#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk grep coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/.config/systemd/user/
mkdir -p /home/user/nginx/
mkdir -p /home/user/app/
mkdir -p /home/user/shared_public/
mkdir -p /home/user/logs/

cat << 'EOF' > /home/user/.config/systemd/user/nginx.service
[Unit]
Description=Nginx User Service

[Service]
ExecStart=/usr/sbin/nginx -c /home/user/nginx/nginx.conf
Restart=always
EOF

cat << 'EOF' > /home/user/.config/systemd/user/api.service
[Unit]
Description=Python API Service

[Service]
ExecStart=/usr/bin/python3 /home/user/app/server.py
Restart=always
EOF

cat << 'EOF' > /home/user/app.env
APP_PORT=8000
EOF

cat << 'EOF' > /home/user/nginx/nginx.conf
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:8001;
        }
        location /static {
            alias /home/user/app/public;
        }
    }
}
events {}
EOF

cat << 'EOF' > /home/user/logs/nginx_access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET / HTTP/1.1" 200 2326
10.0.0.15 - - [10/Oct/2023:13:56:10 -0700] "GET /api HTTP/1.1" 502 154
192.168.1.11 - - [10/Oct/2023:13:56:12 -0700] "GET /api/users HTTP/1.1" 502 154
10.0.0.15 - - [10/Oct/2023:13:56:15 -0700] "GET /api HTTP/1.1" 502 154
172.16.0.5 - - [10/Oct/2023:13:57:00 -0700] "GET / HTTP/1.1" 200 2326
EOF

chmod -R 777 /home/user
