#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required tools
    apt-get install -y nginx qemu-user-static gcc-aarch64-linux-gnu curl wrk

    # Create app directory
    mkdir -p /home/user/app

    # Create nginx.conf
    cat << 'EOF' > /home/user/app/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/app/error.log;
pid /home/user/app/nginx.pid;
events { worker_connections 1024; }
http {
    access_log /home/user/app/access.log;
    upstream backend {
        server 127.0.0.1:8081;
    }
    server {
        listen 8080;
        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

    # Create backend.c
    cat << 'EOF' > /home/user/app/backend.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char *hello = "HTTP/1.1 200 OK\nContent-Type: text/plain\nContent-Length: 2\n\nOK";

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) { exit(EXIT_FAILURE); }
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) { exit(EXIT_FAILURE); }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    // BUG 1: Port mismatch (Nginx expects 8081)
    address.sin_port = htons(8082);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) { exit(EXIT_FAILURE); }
    if (listen(server_fd, 100) < 0) { exit(EXIT_FAILURE); }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) { continue; }
        // BUG 2: Artificial delay causing timeouts
        sleep(1);
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);
        write(new_socket, hello, strlen(hello));
        close(new_socket);
    }
    return 0;
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
