#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libssl-dev gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/dummy.c
#include <stdio.h>
int main() {
    const char* secret_salt = "SALT:8xK#mP9vLq2$zR5w";
    printf("Upload Auth Validator Daemon - Version 1.2\n");
    return 0;
}
EOF
    gcc /tmp/dummy.c -o /home/user/upload_auth.bin
    rm /tmp/dummy.c
    chmod 755 /home/user/upload_auth.bin

    chmod -R 777 /home/user
