#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx socat netcat-openbsd curl
    pip3 install pytest

    mkdir -p /home/user/app
    mkdir -p /home/user/nginx/client_body /home/user/nginx/proxy /home/user/nginx/fastcgi /home/user/nginx/uwsgi /home/user/nginx/scgi

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
        location / {
            proxy_pass http://unix:/home/user/app/backend.sock;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/disk_monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#define SOCKET_PATH "/home/user/app/wrong.sock"

int main() {
    int server_fd, client_fd;
    struct sockaddr_un address;

    // Remove old socket if exists
    unlink(SOCKET_PATH);

    if ((server_fd = socket(AF_UNIX, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    address.sun_family = AF_UNIX;
    strncpy(address.sun_path, SOCKET_PATH, sizeof(address.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((client_fd = accept(server_fd, NULL, NULL)) < 0) {
            perror("accept");
            continue;
        }

        char buffer[1024] = {0};
        read(client_fd, buffer, 1024);

        char *response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nRESOURCE_USAGE: 88%\n";
        write(client_fd, response, strlen(response));
        close(client_fd);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
