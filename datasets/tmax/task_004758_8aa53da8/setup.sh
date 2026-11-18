#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip gcc libc-dev binutils systemd logrotate curl netcat
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/legacy_logs

    # Create the C source code for the legacy binary
    cat << 'EOF' > /tmp/legacy_data_node.c
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

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        exit(EXIT_FAILURE);
    }
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(7331);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        exit(EXIT_FAILURE);
    }
    if (listen(server_fd, 3) < 0) {
        exit(EXIT_FAILURE);
    }

    FILE *log_file = fopen("/home/user/legacy_logs/node.log", "a");
    if (log_file) {
        fprintf(log_file, "Service started on port 7331\n");
        fflush(log_file);
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            continue;
        }

        int valread = read(new_socket, buffer, 1024);
        if (valread > 0) {
            buffer[valread] = '\0';
            if (strncmp(buffer, "STATUS_CHECK", 12) == 0) {
                char *hello = "DATA_NODE_OK_V9\n";
                send(new_socket, hello, strlen(hello), 0);
                if (log_file) {
                    fprintf(log_file, "Status check requested and fulfilled.\n");
                    fflush(log_file);
                }
            } else {
                char *err = "ERROR\n";
                send(new_socket, err, strlen(err), 0);
            }
        }
        close(new_socket);
    }
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_data_node.c -o /app/legacy_data_node
    strip /app/legacy_data_node
    rm /tmp/legacy_data_node.c

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/legacy_logs
    chmod -R 777 /home/user
