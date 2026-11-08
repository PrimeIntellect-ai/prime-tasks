#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc netcat-openbsd
    pip3 install pytest

    mkdir -p /home/user/src /home/user/config /home/user/logs /home/user/run /home/user/bin

    # Write system.env
    cat << 'EOF' > /home/user/config/system.env
BACKEND_IP=127.0.0.1
BACKEND_PORT=9090
FRONTEND_PORT=8080
EOF

    # Write backend.c
    cat << 'EOF' > /home/user/src/backend.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main(int argc, char *argv[]) {
    int port = getenv("BACKEND_PORT") ? atoi(getenv("BACKEND_PORT")) : 9090;
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) exit(EXIT_FAILURE);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
        read(new_socket, buffer, 1024);
        char *hello = "BACKEND_OK\n";
        send(new_socket, hello, strlen(hello), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    # Write frontend.c with hardcoded bad IP
    cat << 'EOF' > /home/user/src/frontend.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int check_backend() {
    int sock = 0;
    struct sockaddr_in serv_addr;
    char buffer[1024] = {0};
    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) return 0;

    serv_addr.sin_family = AF_INET;
    // MISCONFIGURATION HERE
    serv_addr.sin_port = htons(9090);
    if(inet_pton(AF_INET, "192.168.99.99", &serv_addr.sin_addr)<=0) return 0;

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) return 0;
    send(sock, "PING\n", 5, 0);
    read(sock, buffer, 1024);
    close(sock);
    if (strstr(buffer, "BACKEND_OK") != NULL) return 1;
    return 0;
}

int main(int argc, char *argv[]) {
    int port = getenv("FRONTEND_PORT") ? atoi(getenv("FRONTEND_PORT")) : 8080;
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) exit(EXIT_FAILURE);

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
        memset(buffer, 0, sizeof(buffer));
        read(new_socket, buffer, 1024);

        if (strncmp(buffer, "HEALTH_CHECK", 12) == 0) {
            if (check_backend()) {
                send(new_socket, "FRONTEND: OK\n", 13, 0);
            } else {
                send(new_socket, "FRONTEND: ERROR\n", 16, 0);
            }
        }
        close(new_socket);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
