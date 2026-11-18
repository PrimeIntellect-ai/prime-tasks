#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    upstream backend {
        server unix:/home/user/app/wrong.sock;
    }

    server {
        listen 80;
        server_name localhost;

        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/nginx/logs/error.log
2023/11/01 10:15:05 [info] 1000#0: system started
2023/11/01 10:16:22 [error] 1234#0: *1 connect() to unix:/home/user/app/wrong.sock failed (2: No such file or directory) while connecting to upstream, client: 10.0.0.5, server: localhost, request: "GET /api HTTP/1.1", upstream: "http://unix:/home/user/app/wrong.sock:/api", host: "localhost"
2023/11/01 10:18:45 [error] 1234#0: *2 connect() to unix:/home/user/app/wrong.sock failed (2: No such file or directory) while connecting to upstream, client: 172.16.0.12, server: localhost, request: "POST /login HTTP/1.1", upstream: "http://unix:/home/user/app/wrong.sock:/login", host: "localhost"
EOF

    chmod -R 777 /home/user
