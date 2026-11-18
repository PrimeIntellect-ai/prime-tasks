#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    cd /home/user

    cat << 'EOF' > legacy_worker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

#define LEGACY_TOKEN "OLD_COMPROMISED_KEY_9921"
#define BUFFER_SIZE 2048

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <port>\n", argv[0]);
        return 1;
    }

    int port = atoi(argv[1]);
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[BUFFER_SIZE] = {0};

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) exit(EXIT_FAILURE);

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr("127.0.0.1");
    address.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

    while (1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) exit(EXIT_FAILURE);
        read(new_socket, buffer, BUFFER_SIZE);

        char *expected_header = "Authorization: Bearer " LEGACY_TOKEN;
        char *response;

        if (strstr(buffer, expected_header) != NULL) {
            response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nSuccess!";
        } else {
            response = "HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\n\r\nAccess Denied";
        }

        write(new_socket, response, strlen(response));
        close(new_socket);
        memset(buffer, 0, BUFFER_SIZE);
    }
    return 0;
}
EOF

    gcc legacy_worker.c -o legacy_worker
    rm legacy_worker.c

    chmod -R 777 /home/user
