#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/client.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int sock = 0;
    struct sockaddr_in serv_addr;

    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        printf("\n Socket creation error \n");
        return -1;
    }

    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(9090);

    if (inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr) <= 0) {
        printf("\nInvalid address/ Address not supported \n");
        return -1;
    }

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        // BUG: Missing error handling here
        return -1;
    }

    printf("Connected successfully\n");
    close(sock);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/netclient.service
[Unit]
Description=Network Monitoring Client Agent

[Service]
Type=simple
ExecStart=/home/user/app/client
Restart=on-failure

[Install]
WantedBy=default.target
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
