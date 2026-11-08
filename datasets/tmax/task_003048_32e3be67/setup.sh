#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make nginx curl tar
    pip3 install pytest

    mkdir -p /home/user/backend
    mkdir -p /home/user/nginx/logs
    mkdir -p /home/user/nginx/tmp/client_body
    mkdir -p /home/user/nginx/tmp/proxy
    mkdir -p /home/user/backup

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx/tmp/client_body;
    proxy_temp_path /home/user/nginx/tmp/proxy;
    access_log /home/user/nginx/logs/access.log;

    server {
        listen 8080;
        server_name localhost;

        location /api/ {
            proxy_pass http://unix:/tmp/missing_backend.sock;
            proxy_set_header Host $host;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/backend/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>

#define SOCKET_PATH "/tmp/unsafe_backend.sock"

int main() {
    int server_fd, client_fd;
    struct sockaddr_un address;

    unlink(SOCKET_PATH);

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd == 0) {
        perror("Socket failed");
        exit(EXIT_FAILURE);
    }

    address.sun_family = AF_UNIX;
    strcpy(address.sun_path, SOCKET_PATH);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("Bind failed");
        exit(EXIT_FAILURE);
    }

    // Insecure: no permissions applied here currently

    if (listen(server_fd, 3) < 0) {
        perror("Listen failed");
        exit(EXIT_FAILURE);
    }

    char buffer[1024] = {0};
    char *response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"secure\"}";

    while(1) {
        client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) {
            continue;
        }
        read(client_fd, buffer, 1024);
        write(client_fd, response, strlen(response));
        close(client_fd);
    }

    close(server_fd);
    unlink(SOCKET_PATH);
    return 0;
}
EOF

    chmod 644 /home/user/backend/server.c
    chmod 644 /home/user/nginx/nginx.conf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
