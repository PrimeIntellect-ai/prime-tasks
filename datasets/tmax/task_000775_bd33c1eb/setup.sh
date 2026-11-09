#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev systemd openssh-server openssh-client curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/certs
    mkdir -p /home/user/.config/systemd/user
    mkdir -p /home/user/.ssh

    echo "dummy crt" > /home/user/certs/server.crt
    echo "dummy key" > /home/user/certs/server.key

    cat << 'EOF' > /home/user/app/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int main() {
    char *cert_dir = getenv("APP_CERTS_DIR");
    char key_path[256];
    // BUG: strlen(cert_dir) will segfault if cert_dir is NULL
    if (strlen(cert_dir) + 15 > sizeof(key_path)) return 1;
    sprintf(key_path, "%s/server.key", cert_dir);

    FILE *f = fopen(key_path, "r");
    if (!f) {
        fprintf(stderr, "Failed to load certs\n");
        return 1;
    }
    fclose(f);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(4433);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        int new_socket = accept(server_fd, NULL, NULL);
        char *resp = "HTTP/1.1 200 OK\r\nContent-Length: 16\r\n\r\nSECURE_SERVER_OK";
        write(new_socket, resp, strlen(resp));
        close(new_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/secure-backend.service
[Unit]
Description=Secure Backend Service

[Service]
ExecStart=/home/user/app/server
Restart=always

[Install]
WantedBy=default.target
EOF

    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cp /home/user/.ssh/id_rsa.pub /home/user/.ssh/authorized_keys

    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/id_rsa
    chmod 644 /home/user/.ssh/id_rsa.pub
    chmod 600 /home/user/.ssh/authorized_keys
