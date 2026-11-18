#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx golang cron curl
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create Nginx temp directories
    mkdir -p /home/user/client_body /home/user/proxy_temp /home/user/fastcgi_temp /home/user/uwsgi_temp /home/user/scgi_temp

    # Create Nginx configuration
    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
pid /home/user/nginx.pid;
error_log /home/user/error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/client_body;
    proxy_temp_path /home/user/proxy_temp;
    fastcgi_temp_path /home/user/fastcgi_temp;
    uwsgi_temp_path /home/user/uwsgi_temp;
    scgi_temp_path /home/user/scgi_temp;

    access_log /home/user/access.log;

    server {
        listen 127.0.0.1:8888;
        server_name localhost;

        location / {
            proxy_pass http://unix:/home/user/backend.sock;
            proxy_set_header Host $host;
        }
    }
}
EOF

    # Fix permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
