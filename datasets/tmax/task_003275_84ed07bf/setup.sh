#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx/conf
    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/app/run
    mkdir -p /home/user/app/logs

    cat << 'EOF' > /home/user/nginx/conf/nginx.conf
worker_processes  1;
error_log  /home/user/nginx/logs/error.log;
pid        /home/user/nginx/nginx.pid;
events {
    worker_connections  1024;
}
http {
    server {
        listen       8080;
        server_name  localhost;
        location / {
            proxy_pass http://unix:/home/user/app/run/wrong_backend.sock;
        }
    }
}
EOF

    touch /home/user/app/run/backend.sock

    cat << 'EOF' > /home/user/nginx/logs/error.log
2023/10/24 10:15:01 [crit] 12345#0: *1 connect() to unix:/home/user/app/run/wrong_backend.sock failed (2: No such file or directory) while connecting to upstream, client: 127.0.0.1, server: localhost, request: "GET / HTTP/1.1", upstream: "http://unix:/home/user/app/run/wrong_backend.sock:/", host: "localhost:8080"
2023/10/24 11:20:05 [crit] 12345#0: *2 connect() to unix:/home/user/app/run/wrong_backend.sock failed (2: No such file or directory) while connecting to upstream, client: 127.0.0.1, server: localhost, request: "GET /api HTTP/1.1", upstream: "http://unix:/home/user/app/run/wrong_backend.sock:/api", host: "localhost:8080"
2023/10/24 12:25:10 [crit] 12345#0: *3 connect() to unix:/home/user/app/run/wrong_backend.sock failed (2: No such file or directory) while connecting to upstream, client: 127.0.0.1, server: localhost, request: "POST /data HTTP/1.1", upstream: "http://unix:/home/user/app/run/wrong_backend.sock:/data", host: "localhost:8080"
2023/10/24 13:30:15 [crit] 12345#0: *4 connect() to unix:/home/user/app/run/wrong_backend.sock failed (2: No such file or directory) while connecting to upstream, client: 127.0.0.1, server: localhost, request: "GET /status HTTP/1.1", upstream: "http://unix:/home/user/app/run/wrong_backend.sock:/status", host: "localhost:8080"
2023/10/24 14:35:20 [crit] 12345#0: *5 connect() to unix:/home/user/app/run/wrong_backend.sock failed (2: No such file or directory) while connecting to upstream, client: 127.0.0.1, server: localhost, request: "GET / HTTP/1.1", upstream: "http://unix:/home/user/app/run/wrong_backend.sock:/", host: "localhost:8080"
2023/10/24 15:40:25 [crit] 12345#0: *6 connect() to unix:/home/user/app/run/wrong_backend.sock failed (2: No such file or directory) while connecting to upstream, client: 127.0.0.1, server: localhost, request: "GET / HTTP/1.1", upstream: "http://unix:/home/user/app/run/wrong_backend.sock:/", host: "localhost:8080"
EOF

    echo "Log entry 1" > /home/user/app/logs/app.log
    echo "Log entry 2" >> /home/user/app/logs/app.log

    chmod -R 777 /home/user
