#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl tar
    pip3 install pytest

    mkdir -p /home/user/migration/src
    mkdir -p /home/user/migration/backup
    mkdir -p /home/user/migration/socket
    mkdir -p /home/user/migration/bin
    mkdir -p /home/user/migration/logs

    cat << 'EOF' > /home/user/migration/src/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int main() {
    int server_fd, client_fd;
    struct sockaddr_un address;
    // Bug to be fixed by agent
    char *socket_path = "/home/user/migration/wrong.sock";

    unlink(socket_path);

    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    memset(&address, 0, sizeof(struct sockaddr_un));
    address.sun_family = AF_UNIX;
    strncpy(address.sun_path, socket_path, sizeof(address.sun_path) - 1);

    bind(server_fd, (struct sockaddr *)&address, sizeof(struct sockaddr_un));
    listen(server_fd, 5);

    FILE *f = fopen("/home/user/migration/logs/app.log", "a");
    if(f) { fprintf(f, "Server started\n"); fflush(f); }

    while(1) {
        client_fd = accept(server_fd, NULL, NULL);
        if (client_fd > 0) {
            char buffer[1024];
            read(client_fd, buffer, sizeof(buffer));
            char *response = "HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nHello Server!";
            write(client_fd, response, strlen(response));
            if(f) { fprintf(f, "Request served\n"); fflush(f); }
            close(client_fd);
        }
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
