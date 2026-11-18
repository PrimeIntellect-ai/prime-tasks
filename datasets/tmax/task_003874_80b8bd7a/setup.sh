#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc netcat-openbsd tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/setup_tmp
    cat << 'EOF' > /home/user/setup_tmp/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char *hello = "BACKUP_RESTORE_SUCCESSFUL\n";

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) return 1;
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt))) return 1;

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(80);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) return 1;
    if (listen(server_fd, 3) < 0) return 1;

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
        send(new_socket, hello, strlen(hello), 0);
        close(new_socket);
    }
    return 0;
}
EOF
    cd /home/user/setup_tmp
    tar -czf /home/user/backup.tar.gz server.c
    cd /
    rm -rf /home/user/setup_tmp

    chmod -R 777 /home/user
