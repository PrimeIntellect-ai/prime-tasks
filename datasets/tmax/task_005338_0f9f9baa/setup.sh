#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/http_request.txt
POST /api/deploy_key HTTP/1.1
Host: internal.corp
Cookie: session_token=0318180d211b13100f1527262f272e283129382a3b2b3a283d29442e; user=admin
Content-Type: application/json
Content-Length: 45

{"key": "ssh-rsa AAAAB3NzaC1... admin@corp"}
EOF

    cat << 'EOF' > /home/user/key_manager.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char command[512];
    snprintf(command, sizeof(command), "echo '%s' >> /home/user/managed_authorized_keys", argv[1]);
    system(command);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/sshd_config
PermitRootLogin yes
#PasswordAuthentication yes
PasswordAuthentication yes
EOF

    chmod -R 777 /home/user
