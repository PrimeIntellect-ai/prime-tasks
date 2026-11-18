#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nginx curl bash
    pip3 install pytest

    mkdir -p /home/user/app \
             /home/user/nginx/logs \
             /home/user/run \
             /home/user/nginx/client_body \
             /home/user/nginx/fastcgi_temp \
             /home/user/nginx/proxy_temp \
             /home/user/nginx/scgi_temp \
             /home/user/nginx/uwsgi_temp

    cat << 'EOF' > /home/user/app/server.cpp
#include <iostream>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <string.h>

int main() {
    int server_fd, client_socket;
    struct sockaddr_un address;

    // DELIBERATE ERROR: Wrong socket path
    const char* socket_path = "/home/user/app/wrong.sock";

    if ((server_fd = socket(AF_UNIX, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        return 1;
    }

    address.sun_family = AF_UNIX;
    strncpy(address.sun_path, socket_path, sizeof(address.sun_path) - 1);

    unlink(socket_path);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        return 1;
    }

    if (listen(server_fd, 3) < 0) {
        perror("listen");
        return 1;
    }

    while(true) {
        if ((client_socket = accept(server_fd, NULL, NULL)) < 0) {
            perror("accept");
            continue;
        }

        const char* http_response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 15\r\n\r\nHello from C++!";
        write(client_socket, http_response, strlen(http_response));
        close(client_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/nginx/nginx.conf
worker_processes 1;
pid /home/user/nginx/nginx.pid;
error_log /home/user/nginx/logs/error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/nginx/client_body;
    fastcgi_temp_path /home/user/nginx/fastcgi_temp;
    proxy_temp_path /home/user/nginx/proxy_temp;
    scgi_temp_path /home/user/nginx/scgi_temp;
    uwsgi_temp_path /home/user/nginx/uwsgi_temp;

    access_log /home/user/nginx/logs/access.log;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://unix:/home/user/run/upstream.sock;
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
