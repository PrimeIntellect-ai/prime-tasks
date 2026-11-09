#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc netcat-openbsd socat
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backend.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define SOCKET_PATH "/home/user/run/old_socket.sock"

int main() {
    int server_fd, client_fd;
    struct sockaddr_un addr;
    char buffer[1024] = {0};

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);
    unlink(SOCKET_PATH);

    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        perror("bind failed");
        exit(1);
    }

    listen(server_fd, 5);
    printf("Backend listening on %s...\n", SOCKET_PATH);
    fflush(stdout);

    while (1) {
        client_fd = accept(server_fd, NULL, NULL);
        if (client_fd >= 0) {
            int valread = read(client_fd, buffer, 1024);
            if(valread > 0) {
                send(client_fd, "ACK\n", 4, 0);
            }
            close(client_fd);
        }
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
