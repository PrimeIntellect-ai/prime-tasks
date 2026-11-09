#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc nginx curl
pip3 install pytest

mkdir -p /app

cat << 'EOF' > /app/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            # BUG: missing proxy configuration
        }
    }
}
EOF

cat << 'EOF' > /app/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

void normalize_embedding(float* vec, int len) {
    float sum = 0.0;
    for(int i=0; i<len; i++) sum += vec[i]*vec[i];
    int norm = sqrt(sum); // BUG: int cast causes severe precision loss
    if (norm > 0) {
        for(int i=0; i<len; i++) vec[i] /= norm;
    }
}

void handle_client(int client_socket) {
    char buffer[1024] = {0};
    int valread = read(client_socket, buffer, 1024);
    if (valread <= 0) {
        close(client_socket);
        return;
    }

    int id = 1;
    char *id_str = strstr(buffer, "id=");
    if (id_str) {
        id = atoi(id_str + 3);
    }

    int len = 3;
    float vec[3];
    for(int i=0; i<len; i++) vec[i] = (float)(id + i);

    normalize_embedding(vec, len);

    char response[1024];
    sprintf(response, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"id\": %d, \"embedding\": [%f, %f, %f]}\n", id, vec[0], vec[1], vec[2]);
    write(client_socket, response, strlen(response));
    close(client_socket);
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

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
    address.sin_port = htons(9000);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            continue;
        }
        handle_client(new_socket);
    }
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
