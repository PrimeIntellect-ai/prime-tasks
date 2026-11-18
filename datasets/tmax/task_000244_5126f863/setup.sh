#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup directories
    mkdir -p /home/user/app
    mkdir -p /home/user/backend
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Create backend health file
    echo -n "OK" > /home/user/backend/health

    # Create Nginx configuration
    cat << 'EOF' > /home/user/app/nginx.conf
worker_processes 1;
pid /home/user/app/nginx.pid;
events {
    worker_connections 1024;
}
http {
    client_body_temp_path /home/user/app/client_body;
    proxy_temp_path /home/user/app/proxy;
    fastcgi_temp_path /home/user/app/fastcgi;
    uwsgi_temp_path /home/user/app/uwsgi;
    scgi_temp_path /home/user/app/scgi;
    access_log /home/user/app/access.log;
    error_log /home/user/app/error.log;

    server {
        listen 8080;
        server_name localhost;
        location / {
            proxy_pass http://127.0.0.1:9000;
        }
    }
}
EOF

    # Create Nginx temp directories
    mkdir -p /home/user/app/client_body /home/user/app/proxy /home/user/app/fastcgi /home/user/app/uwsgi /home/user/app/scgi

    # Populate corpus
    for i in 1 2 3 4 5; do
        echo "../../etc/passwd" > /app/corpus/evil/payload_$i.txt
        echo "%2e%2e%2fshadow" > /app/corpus/evil/payload_url_$i.txt
        echo "/api/v1/users" > /app/corpus/clean/payload_$i.txt
        echo "/home/index.html" > /app/corpus/clean/payload_html_$i.txt
    done

    # Set permissions
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
