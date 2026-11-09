#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config /home/user/src /home/user/bin /home/user/run

    cat << 'EOF' > /home/user/config/backup_vars.conf
RESTORE_ID=84931
TARGET_ENV=staging
SOCKET_PATH=/home/user/run/monitor.sock
TIMEOUT=300
EOF

    cat << 'EOF' > /home/user/src/restore_monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int main() {
    int server_fd;
    struct sockaddr_un server_addr;

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
        exit(1);
    }

    memset(&server_addr, 0, sizeof(struct sockaddr_un));
    server_addr.sun_family = AF_UNIX;

    // HARDCODED PATH TO REPLACE
    strncpy(server_addr.sun_path, "/var/run/restore.sock", sizeof(server_addr.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr *) &server_addr, sizeof(struct sockaddr_un)) < 0) {
        perror("bind");
        exit(1);
    }

    printf("Listening on socket\n");
    close(server_fd);
    return 0;
}
EOF

    chmod -R 777 /home/user
