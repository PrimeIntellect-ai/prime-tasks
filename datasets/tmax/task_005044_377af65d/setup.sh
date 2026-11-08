#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx build-essential wrk imagemagick
    pip3 install pytest

    # Create app directory
    mkdir -p /app

    # Generate architecture diagram
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 20 \
      -draw "text 10,50 'NGINX PROXY PORT: 8080'" \
      -draw "text 10,100 'UPSTREAM 1: 127.0.0.1:9001'" \
      -draw "text 10,150 'UPSTREAM 2: 127.0.0.1:9002'" \
      /app/architecture.png

    # Create user
    useradd -m -s /bin/bash user || true

    # Create Nginx configuration
    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
error_log /var/log/nginx/error.log;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    upstream backend {
        server 127.0.0.1:8001;
        server 127.0.0.1:8002;
    }

    server {
        listen 80;

        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

    # Create C backend
    cat << 'EOF' > /home/user/backend.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main(int argc, char const *argv[]) {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};
    char *hello = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080); // Hardcoded port

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 1) < 0) { // Small backlog
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            exit(EXIT_FAILURE);
        }

        read(new_socket, buffer, 1024);
        sleep(1); // Artificial sleep
        send(new_socket, hello, strlen(hello), 0);
        close(new_socket);
    }

    return 0;
}
EOF

    chmod -R 777 /home/user
