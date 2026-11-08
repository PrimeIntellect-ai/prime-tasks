#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git nginx gcc libssl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app-config
    mkdir -p /home/user/nginx
    mkdir -p /home/user/deploy.git
    mkdir -p /app

    # Create token generator
    cat << 'EOF' > /tmp/token.c
#include <stdio.h>
#include <string.h>
#include <openssl/sha.h>

void reverse_string(char *str) {
    int n = strlen(str);
    for (int i = 0; i < n / 2; i++) {
        char temp = str[i];
        str[i] = str[n - i - 1];
        str[n - i - 1] = temp;
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char buffer[1024];
    snprintf(buffer, sizeof(buffer), "%s", argv[1]);
    reverse_string(buffer);
    strncat(buffer, "SECRET_SALT_2024", sizeof(buffer) - strlen(buffer) - 1);

    unsigned char hash[SHA256_DIGEST_LENGTH];
    SHA256((unsigned char*)buffer, strlen(buffer), hash);

    for(int i = 0; i < SHA256_DIGEST_LENGTH; i++) {
        printf("%02x", hash[i]);
    }
    printf("\n");
    return 0;
}
EOF
    gcc -o /app/token_generator /tmp/token.c -lssl -lcrypto
    strip -s /app/token_generator
    chmod +x /app/token_generator
    rm /tmp/token.c

    # Create backend
    cat << 'EOF' > /home/user/backend.py
import socket
import os
import http.server

socket_path = '/tmp/app_backend_real.sock'
if os.path.exists(socket_path):
    os.remove(socket_path)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Hello from backend")

class UnixSocketHttpServer(http.server.HTTPServer):
    address_family = socket.AF_UNIX
    def __init__(self, server_address, RequestHandlerClass):
        http.server.HTTPServer.__init__(self, server_address, RequestHandlerClass)

server = UnixSocketHttpServer(socket_path, Handler)
server.serve_forever()
EOF

    # Create nginx config
    cat << 'EOF' > /home/user/app-config/nginx.conf
worker_processes 1;
pid /tmp/nginx.pid;
error_log /tmp/nginx_error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /tmp/client_body;
    proxy_temp_path /tmp/proxy_temp;
    fastcgi_temp_path /tmp/fastcgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;
    scgi_temp_path /tmp/scgi_temp;
    access_log /tmp/nginx_access.log;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://unix:/tmp/app_backend_wrong.sock;
        }
    }
}
EOF

    cp /home/user/app-config/nginx.conf /home/user/nginx/nginx.conf

    # Git init
    cd /home/user/app-config
    git init
    git config user.email "user@example.com"
    git config user.name "User"
    git add nginx.conf
    git commit -m "Initial commit"

    cd /home/user/deploy.git
    git init --bare

    chown -R user:user /home/user
    chmod -R 777 /home/user
