#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev libseccomp-dev netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uploads
    touch /home/user/server.log

    cat << 'EOF' > /home/user/upload_server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

void handle_client(int client_sock) {
    char expected_hash[65] = {0};
    char filename[257] = {0};
    char buffer[1024];
    int bytes_read;

    // Read hash
    read(client_sock, expected_hash, 64);
    // Read filename
    read(client_sock, filename, 256);

    char filepath[512];
    snprintf(filepath, sizeof(filepath), "/home/user/uploads/%s", filename);

    FILE *fp = fopen(filepath, "wb");
    if (!fp) {
        close(client_sock);
        return;
    }

    while ((bytes_read = read(client_sock, buffer, sizeof(buffer))) > 0) {
        fwrite(buffer, 1, bytes_read, fp);
    }

    fclose(fp);
    close(client_sock);
}

int main() {
    int server_sock, client_sock;
    struct sockaddr_in server_addr, client_addr;
    socklen_t client_len = sizeof(client_addr);

    server_sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(9000);

    bind(server_sock, (struct sockaddr *)&server_addr, sizeof(server_addr));
    listen(server_sock, 5);

    while (1) {
        client_sock = accept(server_sock, (struct sockaddr *)&client_addr, &client_len);
        handle_client(client_sock);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
