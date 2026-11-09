#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx gcc build-essential curl
    pip3 install pytest

    mkdir -p /home/user/restore/src
    mkdir -p /home/user/restore/run
    mkdir -p /home/user/restore/bin
    mkdir -p /home/user/restore/logs
    mkdir -p /home/user/restore/client_body_temp
    mkdir -p /home/user/restore/proxy_temp
    mkdir -p /home/user/restore/fastcgi_temp
    mkdir -p /home/user/restore/uwsgi_temp
    mkdir -p /home/user/restore/scgi_temp

    cat << 'EOF' > /home/user/restore/nginx.conf
worker_processes 1;
error_log logs/error.log;
pid run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log logs/access.log;

    server {
        listen 127.0.0.1:8080;
        server_name localhost;

        location /api {
            proxy_pass http://unix:/home/user/restore/run/wrong_path.sock;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/restore/src/backend.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#define SOCKET_PATH "/tmp/old_backend.sock"

int main() {
    int server_fd, client_fd;
    struct sockaddr_un server_addr;
    char buffer[1024];

    // Remove existing socket file if it exists
    unlink(SOCKET_PATH);

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
        exit(EXIT_FAILURE);
    }

    memset(&server_addr, 0, sizeof(struct sockaddr_un));
    server_addr.sun_family = AF_UNIX;
    strncpy(server_addr.sun_path, SOCKET_PATH, sizeof(server_addr.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr *) &server_addr, sizeof(struct sockaddr_un)) < 0) {
        perror("bind");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 5) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    // Task requires writing PID to /home/user/restore/run/backend.pid
    // Agent must implement this.

    const char *response = "HTTP/1.1 200 OK\r\nContent-Length: 17\r\nConnection: close\r\n\r\nANALYTICS_RESTORE";

    while (1) {
        client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) continue;

        read(client_fd, buffer, sizeof(buffer) - 1);
        write(client_fd, response, strlen(response));
        close(client_fd);
    }

    close(server_fd);
    unlink(SOCKET_PATH);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
