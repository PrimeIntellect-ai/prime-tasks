#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl
    pip3 install pytest

    mkdir -p /app/net-bridge-c/src

    cat << 'EOF' > /app/net-bridge-c/Makefile
all:
	gcc -o gateway src/gateway.c
EOF

    cat << 'EOF' > /app/net-bridge-c/src/gateway.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <pthread.h>

void *handle_client(void *arg) {
    int client_fd = *((int *)arg);
    free(arg);
    char buffer[1024] = {0};
    read(client_fd, buffer, 1024);
    if (strstr(buffer, "GET /ping ") != NULL) {
        char *response = "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nPONG";
        write(client_fd, response, strlen(response));
    } else if (strstr(buffer, "GET /crash ") != NULL) {
        exit(1);
    }
    close(client_fd);
    return NULL;
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    int port = 8080; // atoi(getenv("BIND_PORT"));

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while (1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            exit(EXIT_FAILURE);
        }
        pthread_t thread_id;
        int *client_fd = malloc(sizeof(int));
        *client_fd = new_socket;
        pthread_create(&thread_id, NULL, handle_client, (void *)client_fd);
        pthread_detach(thread_id);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/net-bridge-c
