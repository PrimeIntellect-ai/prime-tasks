#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip iptables nginx
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/app/run
    mkdir -p /home/user/app/logs
    mkdir -p /home/user/app/tmp

    # Create the real socket file
    touch /home/user/app/run/gunicorn.sock

    # Create the broken nginx.conf
    cat << 'EOF' > /home/user/app/nginx.conf
server {
    listen 8080;
    server_name localhost;

    location / {
        proxy_pass http://unix:/home/user/app/gunicorn.sock;
        proxy_set_header Host $host;
    }
}
EOF

    # Create the error log with mocked 502 connection errors
    cat << 'EOF' > /home/user/app/logs/error.log
2023/10/24 10:00:00 [error] 1234#0: *1 connect() to unix:/home/user/app/gunicorn.sock failed (2: No such file or directory) while connecting to upstream, client: 127.0.0.1, server: _, request: "GET / HTTP/1.1", upstream: "http://unix:/home/user/app/gunicorn.sock:/", host: "localhost"
2023/10/24 10:01:23 [info] 1234#0: *2 client closed connection while waiting for request, client: 127.0.0.1, server: 0.0.0.0:8080
2023/10/24 10:05:10 [error] 1234#0: *3 connect() to unix:/home/user/app/tmp/gunicorn.sock failed (2: No such file or directory) while connecting to upstream, client: 127.0.0.1, server: _, request: "GET /api HTTP/1.1", upstream: "http://unix:/home/user/app/tmp/gunicorn.sock:/api", host: "localhost"
2023/10/24 10:05:15 [error] 1234#0: *4 connect() to unix:/home/user/app/gunicorn.sock failed (2: No such file or directory) while connecting to upstream, client: 127.0.0.1, server: _, request: "GET / HTTP/1.1", upstream: "http://unix:/home/user/app/gunicorn.sock:/", host: "localhost"
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
