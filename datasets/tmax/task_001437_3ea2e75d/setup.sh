#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/
    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/error.log;
pid /home/user/nginx.pid;
events {
    worker_connections 1024;
}
http {
    access_log /home/user/access.log;
    client_body_temp_path /home/user/client_body;
    fastcgi_temp_path /home/user/fastcgi_temp;
    proxy_temp_path /home/user/proxy_temp;
    scgi_temp_path /home/user/scgi_temp;
    uwsgi_temp_path /home/user/uwsgi_temp;

    server {
        listen 127.0.0.1:8081;
        location / {
            proxy_pass http://127.0.0.1:9090;
        }
    }
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
