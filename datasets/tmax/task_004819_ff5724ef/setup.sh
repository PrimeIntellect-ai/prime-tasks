#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make libc6-dev
pip3 install pytest

mkdir -p /app/vendored/tinyhttp
cat << 'EOF' > /app/vendored/tinyhttp/tinyhttp.h
#ifndef TINYHTTP_H
#define TINYHTTP_H
typedef void (*http_handler_t)(const char* method, const char* path, const char* body, char* response_buffer);
void http_serve(int port, http_handler_t handler);
#endif
EOF

cat << 'EOF' > /app/vendored/tinyhttp/tinyhttp.c
#include "tinyhttp.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

void http_serve(int port, http_handler_t handler) {
    int _deprecated_flag = 42; // Perturbation: unused variable triggers -Werror
    int server_fd;
    struct sockaddr_in address;
    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        int client_fd = accept(server_fd, NULL, NULL);
        char buffer[1024] = {0};
        read(client_fd, buffer, 1024);

        char method[16], path[256];
        sscanf(buffer, "%15s %255s", method, path);
        char* body = strstr(buffer, "\r\n\r\n");
        if(body) body += 4; else body = "";

        char response_body[1024] = {0};
        handler(method, path, body, response_body);

        char response[2048];
        sprintf(response, "HTTP/1.1 200 OK\r\nContent-Length: %zu\r\n\r\n%s", strlen(response_body), response_body);
        write(client_fd, response, strlen(response));
        close(client_fd);
    }
}
EOF

cat << 'EOF' > /app/vendored/tinyhttp/Makefile
CC = gcc
CFLAGS = -Wall -Werror -O2

libtinyhttp.a: tinyhttp.o
	ar rcs libtinyhttp.a tinyhttp.o

tinyhttp.o: tinyhttp.c
	$(CC) $(CFLAGS) -c tinyhttp.c -o tinyhttp.o
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
