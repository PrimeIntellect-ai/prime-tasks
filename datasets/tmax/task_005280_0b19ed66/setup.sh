#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx gcc curl psmisc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/nginx/logs /home/user/nginx/tmp /home/user/run /home/user/src /home/user/bin /home/user/logs /home/user/mail
    touch /home/user/mail/alerts.mbox

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
    fastcgi_temp_path /home/user/nginx/tmp/fastcgi;
    uwsgi_temp_path /home/user/nginx/tmp/uwsgi;
    scgi_temp_path /home/user/nginx/tmp/scgi;

    access_log /home/user/nginx/logs/access.log;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://unix:/home/user/run/backend.sock;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/src/monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#define SOCKET_PATH "/home/user/run/health_monitor.sock"

int main() {
    int server_fd, client_fd;
    struct sockaddr_un server_addr;
    char buffer[1024];

    unlink(SOCKET_PATH);
    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) exit(1);

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sun_family = AF_UNIX;
    strncpy(server_addr.sun_path, SOCKET_PATH, sizeof(server_addr.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) exit(1);
    if (listen(server_fd, 5) < 0) exit(1);

    while (1) {
        client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) continue;

        int bytes_read = read(client_fd, buffer, sizeof(buffer) - 1);
        if (bytes_read > 0) {
            buffer[bytes_read] = '\0';
            // Bug: Invalid HTTP response (missing \r\n\r\n)
            char *response = "HTTP/1.1 200 OK\nSTATUS: UP\n";
            write(client_fd, response, strlen(response));
        }
        close(client_fd);
    }
    close(server_fd);
    return 0;
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
