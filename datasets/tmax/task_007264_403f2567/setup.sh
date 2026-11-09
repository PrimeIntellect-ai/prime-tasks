#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip software-properties-common wget socat gcc netcat-openbsd
    add-apt-repository -y ppa:apptainer/ppa
    apt-get update
    apt-get install -y apptainer
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user
    apptainer pull busybox.sif docker://busybox:latest

    cat << 'EOF' > /home/user/healthcheck.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    FILE *f = fopen("/home/user/app_users.txt", "r");
    if (!f) {
        printf("Cannot open user file\n");
        return 1;
    }

    char line[256];
    int auth = 0;
    while (fgets(line, sizeof(line), f)) {
        // BUG: Incorrect string comparison
        if (strncmp(line, "admin:network_engine", 20) != 0) { 
            auth = 1;
        }
    }
    fclose(f);

    if (!auth) {
        printf("Auth failed\n");
        return 1;
    }

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in server;
    server.sin_family = AF_INET;
    // BUG: Connecting to wrong port
    server.sin_port = htons(8081);
    server.sin_addr.s_addr = inet_addr("127.0.0.1");

    if (connect(sock, (struct sockaddr *)&server, sizeof(server)) < 0) {
        printf("Connection failed\n");
        return 1;
    }

    char buffer[1024] = {0};
    read(sock, buffer, 1024);
    printf("%s\n", buffer);
    close(sock);
    return 0;
}
EOF

    chown user:user /home/user/healthcheck.c /home/user/busybox.sif
    chmod -R 777 /home/user
