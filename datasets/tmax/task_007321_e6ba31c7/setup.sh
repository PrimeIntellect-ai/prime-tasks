#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl
    pip3 install pytest

    mkdir -p /home/user/incident

    cat << 'EOF' > /home/user/incident/auth_server.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char *qs = argv[1];
    char redirect[256] = "/";
    if (strncmp(qs, "redirect_to=", 12) == 0) {
        strncpy(redirect, qs + 12, 255);
    }
    printf("HTTP/1.1 302 Found\r\n");
    printf("Location: %s\r\n", redirect);
    printf("\r\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/incident/sshd_config
Port 2222
PermitRootLogin yes
PasswordAuthentication yes
X11Forwarding no
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
