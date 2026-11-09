#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make tar netcat wget
    pip3 install pytest

    # Create app directory
    mkdir -p /app/micro-tar-server-1.0

    # Create server.c
    cat << 'EOF' > /app/micro-tar-server-1.0/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include "tar_stream.h"

#define DEFAULT_PORT 80

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    int port = DEFAULT_PORT;
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr("127.0.0.1");
    address.sin_port = htons(port);
    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        return 1;
    }
    listen(server_fd, 3);
    while(1) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) continue;
        char buffer[1024] = {0};
        read(client_fd, buffer, 1024);
        if (strstr(buffer, "Authorization: Bearer ds-secret-token")) {
            char *resp = "HTTP/1.1 200 OK\r\n\r\n";
            write(client_fd, resp, strlen(resp));
            stream_tar(client_fd, argv[1]);
        } else {
            char *resp = "HTTP/1.1 401 Unauthorized\r\n\r\n";
            write(client_fd, resp, strlen(resp));
        }
        close(client_fd);
    }
    return 0;
}
EOF

    # Create tar_stream.c
    cat << 'EOF' > /app/micro-tar-server-1.0/tar_stream.c
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <dirent.h>
#include <string.h>
#include <unistd.h>
#include "tar_stream.h"

void stream_tar(int fd, const char *dir) {
    struct stat st;
    stat(dir, &st); // Agent will change this to lstat and add S_ISLNK logic

    // Underlying functional implementation for the verifier
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "tar -cf - -C %s . >&%d", dir, fd);
    system(cmd);
}
EOF

    # Create tar_stream.h
    cat << 'EOF' > /app/micro-tar-server-1.0/tar_stream.h
void stream_tar(int fd, const char *dir);
EOF

    # Create Makefile
    cat << 'EOF' > /app/micro-tar-server-1.0/Makefile
all:
	gcc server.c tar_stream.c -o micro-tar-server
EOF

    # Create user and dataset
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/dataset_active

    echo "data1" > /home/user/dataset_active/file1.txt
    echo "data2" > /home/user/dataset_active/file2.txt
    ln /home/user/dataset_active/file1.txt /home/user/dataset_active/file1_hardlink.txt
    ln -s file2.txt /home/user/dataset_active/file2_symlink.txt

    chmod -R 777 /home/user
    chmod -R 777 /app
