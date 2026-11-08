#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/backend
    mkdir -p /home/user/client_body /home/user/proxy_temp /home/user/fastcgi_temp /home/user/uwsgi_temp /home/user/scgi_temp

    cat << 'EOF' > /home/user/backend/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include "utils.h"

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char *hello = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nUtility Backend Active\n";

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }
    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    printf("Backend listening on 8080\n");
    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            continue;
        }
        process_request();
        write(new_socket, hello, strlen(hello));
        close(new_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/backend/utils.c
#include <stdio.h>
#include "utils.h"

void process_request() {
    // dummy processing
}
EOF

    cat << 'EOF' > /home/user/backend/utils.h
#ifndef UTILS_H
#define UTILS_H
void process_request();
#endif
EOF

    cat << 'EOF' > /home/user/backend/Makefile
all: server

server: server.o utils.o
	gcc -o server server.o utils.o

server.o: server.c utils.h
	gcc -c server.c

utils.o: utils.c utils.h server.o
	gcc -c utils.c

clean:
	rm -f *.o server
EOF

    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
pid /home/user/nginx.pid;
error_log /home/user/error.log;

events {
    worker_connections 1024;
}

http {
    client_body_temp_path /home/user/client_body;
    proxy_temp_path /home/user/proxy_temp;
    fastcgi_temp_path /home/user/fastcgi_temp;
    uwsgi_temp_path /home/user/uwsgi_temp;
    scgi_temp_path /home/user/scgi_temp;
    access_log /home/user/access.log;

    # Add configuration here
}
EOF

    chown -R user:user /home/user/backend
    chown -R user:user /home/user/nginx.conf /home/user/*_temp /home/user/client_body
    chmod -R 777 /home/user
