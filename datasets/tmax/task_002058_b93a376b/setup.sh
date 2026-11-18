#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/service.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

const char *MASTER_KEY = "W3bS3cur1ty2024!";

void encrypt_token(const char *plaintext, char *hex_out) {
    int len = strlen(plaintext);
    int key_len = strlen(MASTER_KEY);

    for (int i = 0; i < len; i++) {
        unsigned char cipher_byte = plaintext[i] ^ MASTER_KEY[i % key_len];
        sprintf(&hex_out[i * 2], "%02x", cipher_byte);
    }
}

int main(int argc, char *argv[]) {
    // Simulated daemon logic
    // char token_hex[256];
    // encrypt_token(admin_token, token_hex);
    // char cmd[512];
    // snprintf(cmd, sizeof(cmd), "/usr/local/bin/auth_helper --token %s", token_hex);
    // system(cmd);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/process_snaps.log
[08:12:01] CMD: /usr/sbin/nginx -g daemon off;
[08:12:05] CMD: /usr/local/bin/web_daemon --config /etc/web/config.json
[08:14:22] CMD: /bin/bash /opt/scripts/healthcheck.sh
[08:15:33] CMD: /usr/local/bin/auth_helper --token 044612364130101143110d73545f5d4f07521120440c0716084d --user admin
[08:16:10] CMD: /usr/bin/python3 /opt/monitor/metrics.py
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
