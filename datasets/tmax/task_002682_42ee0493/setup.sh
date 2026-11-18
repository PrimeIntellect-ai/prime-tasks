#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx gcc curl
    pip3 install pytest

    mkdir -p /home/user/src

    # Create the Nginx configuration
    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
daemon off;
error_log /home/user/nginx_error.log info;
pid /home/user/nginx.pid;

events {
    worker_connections 1024;
}

http {
    access_log /home/user/nginx_access.log;
    client_body_temp_path /home/user/client_body;
    proxy_temp_path /home/user/proxy_temp;
    fastcgi_temp_path /home/user/fastcgi_temp;
    uwsgi_temp_path /home/user/uwsgi_temp;
    scgi_temp_path /home/user/scgi_temp;

    server {
        listen 8080;
        server_name localhost;

        location / {
            proxy_pass http://unix:/home/user/app/current/backend.sock;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

    # Create the broken C code
    cat << 'EOF' > /home/user/src/backend.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;

    int server_fd, client_fd;
    struct sockaddr_un server_addr;

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);

    server_addr.sun_family = AF_UNIX;
    strncpy(server_addr.sun_path, argv[1], sizeof(server_addr.sun_path) - 1);

    // BUG: Missing unlink(argv[1])
    // BUG: bind missing size
    bind(server_fd, (struct sockaddr *)&server_addr, sizeof(struct sockaddr_un));
    listen(server_fd, 5);

    char response[] = "HTTP/1.1 200 OK\r\nContent-Length: 18\r\nConnection: close\r\n\r\nSUCCESS_DEPLOYMENT";

    while(1) {
        client_fd = accept(server_fd, NULL, NULL);
        // BUG: missing read/write and close
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
