#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils net-tools lsof
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/beacon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int server_fd;
    struct sockaddr_in address;
    int opt = 1;

    // The hardcoded salt that the agent needs to find via strings or objdump
    const char* salt_str = "B34C0N_S4LT_82XF9!";

    // Prevent the variable from being optimized out
    volatile const char* force_keep = salt_str;

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt))) {
        exit(EXIT_FAILURE);
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr("127.0.0.1");
    address.sin_port = htons(28443);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 3) < 0) {
        exit(EXIT_FAILURE);
    }

    // Just hang and listen
    while(1) {
        sleep(10);
    }

    return 0;
}
EOF

    gcc /tmp/beacon.c -o /home/user/suspicious_beacon
    chmod +x /home/user/suspicious_beacon
    rm /tmp/beacon.c

    chmod -R 777 /home/user
