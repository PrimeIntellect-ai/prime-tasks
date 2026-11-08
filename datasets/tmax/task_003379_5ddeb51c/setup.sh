#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx openssh-server curl rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Configure SSH
    mkdir -p /run/sshd
    ssh-keygen -A

    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -b 2048 -f /home/user/.ssh/id_rsa -N ""
    cat /home/user/.ssh/id_rsa.pub >> /home/user/.ssh/authorized_keys
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/authorized_keys
    chmod 600 /home/user/.ssh/id_rsa
    chown -R user:user /home/user/.ssh

    # Nginx setup
    mkdir -p /home/user/nginx/logs /home/user/nginx/temp /home/user/backend/src

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx/temp/client_body;
    proxy_temp_path /home/user/nginx/temp/proxy;
    fastcgi_temp_path /home/user/nginx/temp/fastcgi;
    uwsgi_temp_path /home/user/nginx/temp/uwsgi;
    scgi_temp_path /home/user/nginx/temp/scgi;

    access_log /home/user/nginx/logs/access.log;

    upstream backend {
        server unix:/home/user/nginx/backend.sock;
    }

    server {
        listen 127.0.0.1:8080;
        server_name localhost;

        location / {
            proxy_pass http://backend;
            proxy_set_header Host $host;
        }
    }
}
EOF

    # Rust setup
    cd /home/user/backend && cargo init --bin

    # Start SSH daemon so it's available if the environment preserves background processes
    /usr/sbin/sshd || true

    chmod -R 777 /home/user
