#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/nginx
    mkdir -p /home/user/nginx/client_temp /home/user/nginx/proxy_temp /home/user/nginx/fastcgi_temp /home/user/nginx/uwsgi_temp /home/user/nginx/scgi_temp

    cat << 'EOF' > /home/user/app/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

int main() {
    int server_fd, client_fd;
    struct sockaddr_un addr;

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, "/tmp/wrong.sock", sizeof(addr.sun_path)-1);

    unlink(addr.sun_path);
    bind(server_fd, (struct sockaddr*)&addr, sizeof(addr));
    listen(server_fd, 5);

    while(1) {
        client_fd = accept(server_fd, NULL, NULL);
        if (client_fd > 0) {
            char buffer[1024];
            read(client_fd, buffer, sizeof(buffer)-1);
            char *response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 18\r\n\r\nHello Microservice";
            write(client_fd, response, strlen(response));
            close(client_fd);
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
error_log stderr;
pid /home/user/nginx/nginx.pid;
events { worker_connections 1024; }
http {
    access_log off;
    client_body_temp_path /home/user/nginx/client_temp;
    proxy_temp_path /home/user/nginx/proxy_temp;
    fastcgi_temp_path /home/user/nginx/fastcgi_temp;
    uwsgi_temp_path /home/user/nginx/uwsgi_temp;
    scgi_temp_path /home/user/nginx/scgi_temp;

    server {
        listen 8080;
        location /api {
            proxy_pass http://unix:/home/user/wrong_proxy.sock;
        }
    }
}
EOF

    chmod -R 777 /home/user
