#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        binutils \
        curl \
        gdb \
        strace \
        netcat
    pip3 install pytest requests flask

    # Create the app directory
    mkdir -p /app

    # Write the C source code for the legacy monitoring daemon
    cat << 'EOF' > /tmp/storage_agent.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    char *token = getenv("STORAGE_AUTH_TOKEN");
    if (!token || strcmp(token, "7x9_MONITOR_KEY_x99") != 0) {
        printf("Error: Invalid or missing token.\n");
        return 1;
    }

    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        return 1;
    }
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        perror("setsockopt");
        return 1;
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr("127.0.0.1");
    address.sin_port = htons(9999);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        return 1;
    }
    if (listen(server_fd, 3) < 0) {
        perror("listen");
        return 1;
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            continue;
        }
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);
        if (strncmp(buffer, "GET /raw", 8) == 0) {
            char *response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"disk_used_mb\": 460, \"disk_quota_mb\": 500}";
            write(new_socket, response, strlen(response));
        } else {
            char *response = "HTTP/1.1 404 Not Found\r\n\r\n";
            write(new_socket, response, strlen(response));
        }
        close(new_socket);
    }
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O2 /tmp/storage_agent.c -o /app/storage_agent
    strip /app/storage_agent
    rm /tmp/storage_agent.c

    # Create the user
    useradd -m -s /bin/bash user || true

    # Ensure .bashrc exists
    touch /home/user/.bashrc
    chown user:user /home/user/.bashrc

    # Set permissions
    chmod -R 777 /home/user
