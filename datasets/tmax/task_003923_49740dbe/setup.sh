#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils openssl
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/audit_daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr("127.0.0.1");
    address.sin_port = htons(9000);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        if (new_socket < 0) continue;
        memset(buffer, 0, sizeof(buffer));
        int valread = read(new_socket, buffer, 1024);
        if (valread > 0 && strncmp(buffer, "AUTH_REQ_COMPLIANCE_2024_XYZ\n", 29) == 0) {
            FILE *fp = fopen("/app/logs.txt", "r");
            if (fp) {
                char chunk[1024];
                size_t n;
                while ((n = fread(chunk, 1, sizeof(chunk), fp)) > 0) {
                    if (write(new_socket, chunk, n) < 0) break;
                }
                fclose(fp);
            }
        }
        close(new_socket);
    }
    return 0;
}
EOF

    gcc -O2 /app/audit_daemon.c -o /app/audit_daemon
    strip /app/audit_daemon
    rm /app/audit_daemon.c

    cat << 'EOF' > /app/logs.txt
2024-01-01 10:00:00 User login from 192.168.1.100
2024-01-01 10:05:00 Payment processed 1234-5678-9012-3456
2024-01-01 10:10:00 API key generated a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
2024-01-01 10:15:00 Normal log entry without sensitive data
EOF

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/certs

    chmod -R 777 /app
    chmod -R 777 /home/user
