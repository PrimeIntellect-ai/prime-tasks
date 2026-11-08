#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gdb binutils socat netcat nginx
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>

int main() {
    std::string input;
    std::string line;
    while (std::getline(std::cin, line)) {
        input += line + "\n";
    }

    if (input.find("Subject: URGENT") != std::string::npos) {
        std::cout << "admin-list\n";
    } else if (input.find("To: dev@") != std::string::npos) {
        std::cout << "dev-list\n";
    } else if (input.find("From: spammer@") != std::string::npos) {
        std::cout << "drop\n";
    } else {
        std::cout << "general-inbox\n";
    }
    return 0;
}
EOF
    g++ -O2 /app/oracle.cpp -o /app/email_router_oracle
    strip /app/email_router_oracle
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/nginx

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log /home/user/nginx/error.log;
pid /home/user/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/nginx/access.log;
    client_body_temp_path /home/user/nginx/client_body;
    proxy_temp_path /home/user/nginx/proxy;
    fastcgi_temp_path /home/user/nginx/fastcgi;
    uwsgi_temp_path /home/user/nginx/uwsgi;
    scgi_temp_path /home/user/nginx/scgi;

    server {
        listen 8080;
        server_name localhost;

        location /route {
            proxy_pass http://127.0.0.1:9000;
        }
    }
}
EOF

    chmod -R 777 /home/user
