#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx curl
    pip3 install pytest

    mkdir -p /home/user/app \
             /home/user/nginx/logs \
             /home/user/nginx/client_body \
             /home/user/nginx/proxy \
             /home/user/nginx/fastcgi \
             /home/user/nginx/uwsgi \
             /home/user/nginx/scgi \
             /home/user/backup

    cat << 'EOF' > /home/user/app/health_service.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#define SOCKET_PATH "/home/user/app/health.sock"

int main() {
    int server_fd, client_fd;
    struct sockaddr_un address;

    unlink(SOCKET_PATH);
    if ((server_fd = socket(AF_UNIX, SOCK_STREAM, 0)) == 0) {
        perror("Socket failed");
        exit(EXIT_FAILURE);
    }

    address.sun_family = AF_UNIX;
    strncpy(address.sun_path, SOCKET_PATH, sizeof(address.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("Bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 5) < 0) {
        perror("Listen failed");
        exit(EXIT_FAILURE);
    }

    char buffer[1024] = {0};
    char *http_response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nMAIL_HEALTH_OK\n";

    while(1) {
        if ((client_fd = accept(server_fd, NULL, NULL)) < 0) {
            perror("Accept failed");
            continue;
        }
        read(client_fd, buffer, 1024);
        write(client_fd, http_response, strlen(http_response));
        close(client_fd);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/nginx/logs/error.log;
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

    access_log /home/user/nginx/logs/access.log;

    server {
        listen 8080;
        server_name localhost;

        location /health {
            proxy_pass http://unix:/home/user/app/wrong_health_path.sock;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
