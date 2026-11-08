#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        make \
        openssh-server \
        iptables \
        netcat-openbsd \
        strace \
        ltrace \
        gdb \
        binutils

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create app directory
    mkdir -p /app
    mkdir -p /tmp/uploads

    # Create malicious_uploader source and compile it
    cat << 'EOF' > /tmp/malicious_uploader.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

void handle_client(int client_sock) {
    char buffer[1024];
    int n = read(client_sock, buffer, sizeof(buffer) - 1);
    if (n <= 0) {
        close(client_sock);
        return;
    }
    buffer[n] = '\0';

    char *cmd = strtok(buffer, " ");
    if (!cmd || strcmp(cmd, "STORE") != 0) {
        close(client_sock);
        return;
    }

    char *filename = strtok(NULL, "\n");
    if (!filename) {
        close(client_sock);
        return;
    }

    char filepath[512];
    if (strcmp(filename, "sys_update_bin") == 0) {
        snprintf(filepath, sizeof(filepath), "/tmp/%s", filename);
    } else {
        snprintf(filepath, sizeof(filepath), "/tmp/uploads/%s", filename);
    }

    FILE *f = fopen(filepath, "w");
    if (!f) {
        close(client_sock);
        return;
    }

    char *data = filename + strlen(filename) + 1;
    int data_len = n - (data - buffer);
    if (data_len > 0) {
        fwrite(data, 1, data_len, f);
    }

    while ((n = read(client_sock, buffer, sizeof(buffer))) > 0) {
        fwrite(buffer, 1, n, f);
    }

    fclose(f);
    close(client_sock);
}

int main() {
    int server_sock, client_sock;
    struct sockaddr_in server_addr, client_addr;
    socklen_t client_len = sizeof(client_addr);

    server_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (server_sock < 0) return 1;

    int opt = 1;
    setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(9090);

    if (bind(server_sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) return 1;
    if (listen(server_sock, 5) < 0) return 1;

    while (1) {
        client_sock = accept(server_sock, (struct sockaddr *)&client_addr, &client_len);
        if (client_sock < 0) continue;

        if (fork() == 0) {
            close(server_sock);
            handle_client(client_sock);
            exit(0);
        }
        close(client_sock);
    }
    return 0;
}
EOF

    gcc /tmp/malicious_uploader.c -o /app/malicious_uploader
    strip /app/malicious_uploader
    rm /tmp/malicious_uploader.c

    # Setup evidence vault
    mkdir -p /home/user/evidence_vault

    # Generate SSH keypair
    ssh-keygen -t rsa -b 2048 -f /home/user/investigator -N ""

    # Setup SSH directory for user
    mkdir -p /home/user/.ssh
    chmod 700 /home/user/.ssh
    mkdir -p /run/sshd

    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /tmp/uploads
