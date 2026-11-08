#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ procps
    pip3 install pytest

    mkdir -p /home/user/migration

    cat << 'EOF' > /home/user/migration/backend.cpp
#include <iostream>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <cstring>

int main() {
    int server_fd;
    struct sockaddr_un server_addr;

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        return 1;
    }

    server_addr.sun_family = AF_UNIX;
    // WRONG LEGACY PATH
    strncpy(server_addr.sun_path, "/tmp/legacy_app.sock", sizeof(server_addr.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        return 1;
    }

    if (listen(server_fd, 5) < 0) {
        return 1;
    }

    while (true) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd >= 0) {
            close(client_fd);
        }
    }

    close(server_fd);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
