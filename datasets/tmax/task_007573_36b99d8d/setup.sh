#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc nginx curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/tmp

    cat << 'EOF' > /home/user/metrics_service.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int port = atoi(argv[1]);
    int server_fd;
    struct sockaddr_in address;
    int opt = 1;

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) return 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    // BUG: Missing network byte order conversion
    address.sin_port = port;

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) return 1;
    if (listen(server_fd, 3) < 0) return 1;

    char response[] = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\": \"ok\", \"active_connections\": 42}\n";
    while(1) {
        int new_socket = accept(server_fd, NULL, NULL);
        if (new_socket >= 0) {
            write(new_socket, response, strlen(response));
            close(new_socket);
        }
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
