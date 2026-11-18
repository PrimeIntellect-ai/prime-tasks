#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server nginx imagemagick sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create directories for Nginx
    mkdir -p /home/user/nginx/client_body \
             /home/user/nginx/proxy \
             /home/user/nginx/fastcgi \
             /home/user/nginx/uwsgi \
             /home/user/nginx/scgi

    # Create Nginx config
    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
events {
    worker_connections 1024;
}
http {
    client_body_temp_path /home/user/nginx/client_body;
    proxy_temp_path /home/user/nginx/proxy;
    fastcgi_temp_path /home/user/nginx/fastcgi;
    uwsgi_temp_path /home/user/nginx/uwsgi;
    scgi_temp_path /home/user/nginx/scgi;
    access_log /home/user/nginx/access.log;
    error_log /home/user/nginx/error.log;

    server {
        listen 8080;
        location /api {
            proxy_pass http://localhost:9999;
        }
    }
}
EOF

    # Create arch diagram
    mkdir -p /app
    convert -size 400x200 xc:white -fill black -pointsize 24 -draw "text 50,100 'Backend Port: 9042'" /app/arch_diagram.png

    # Setup SSH
    mkdir -p /var/run/sshd
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cat /home/user/.ssh/id_rsa.pub > /home/user/.ssh/authorized_keys
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/authorized_keys /home/user/.ssh/id_rsa
    echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config

    chown -R user:user /home/user
    chmod -R 777 /home/user
