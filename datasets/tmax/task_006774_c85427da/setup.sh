#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app /home/user/run

    cat << 'EOF' > /home/user/app/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int main() {
    char *env_path = getenv("UPSTREAM_SOCKET");
    struct sockaddr_un addr;
    int fd;

    if (env_path == NULL) {
        printf("No UPSTREAM_SOCKET\n");
        return 1;
    }

    fd = socket(AF_UNIX, SOCK_STREAM, 0);
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    // BUG: truncates path
    strncpy(addr.sun_path, env_path, 10);

    unlink(addr.sun_path);
    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) == -1) {
        perror("bind error");
        return 1;
    }

    listen(fd, 5);
    int client = accept(fd, NULL, NULL);
    write(client, "OK\n", 3);
    close(client);
    close(fd);
    unlink(addr.sun_path);
    return 0;
}
EOF

    chmod -R 777 /home/user
