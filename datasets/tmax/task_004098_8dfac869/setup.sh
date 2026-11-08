#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc netcat-openbsd
    pip3 install pytest

    mkdir -p /home/user/capacity-config
    echo "CAPACITY_LIMIT=8500" > /home/user/capacity-config/settings.conf

    cat << 'EOF' > /home/user/net_sim.py
import time
import socket
import sys

# Simulate slow startup
time.sleep(2)

try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 8888))
    s.listen(1)
    # Keep running so the C program can connect
    time.sleep(10)
except Exception as e:
    sys.exit(1)
EOF

    cat << 'EOF' > /home/user/planner.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
/* MISSING HEADERS INTENTIONALLY FOR THE TASK */
/* #include <sys/socket.h> */
/* #include <arpa/inet.h> */

int main() {
    FILE *fp = fopen("/home/user/config/settings.conf", "r");
    if (!fp) {
        perror("Failed to open config");
        exit(1);
    }

    char buffer[256];
    if (!fgets(buffer, sizeof(buffer), fp)) {
        exit(1);
    }
    fclose(fp);

    // Trim newline
    buffer[strcspn(buffer, "\n")] = 0;

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        perror("Socket creation failed");
        exit(1);
    }

    struct sockaddr_in serv_addr;
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(8888);

    if(inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr) <= 0) {
        perror("Invalid address");
        exit(1);
    }

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        perror("Connection Failed");
        exit(1);
    }

    printf("Connection successful. Configuration loaded: %s\n", buffer);
    close(sock);

    /* Missing return 0; intentionally */
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
