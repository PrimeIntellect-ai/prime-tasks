#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make valgrind netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/api_client.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;

    char *payload = argv[1];
    char *request = malloc(256);
    snprintf(request, 256, "GET /api/verify?payload=%s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n", payload);

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in server;
    server.sin_family = AF_INET;
    server.sin_port = htons(8080);
    server.sin_addr.s_addr = inet_addr("127.0.0.1");

    if (connect(sock, (struct sockaddr *)&server, sizeof(server)) < 0) {
        return 1;
    }

    send(sock, request, strlen(request), 0);

    char response[1024] = {0};
    recv(sock, response, 1023, 0);

    char *body = strstr(response, "\r\n\r\n");
    if (body) {
        printf("%s\n", body + 4);
    }

    close(sock);
    // LEAK: memory not freed
    return 0;
}
EOF

    chmod -R 777 /home/user
