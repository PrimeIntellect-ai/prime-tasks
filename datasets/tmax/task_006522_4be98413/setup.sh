#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/.secret_logs.txt
[INFO] Admin login from 10.0.5.15
[WARN] Failed attempt from 192.168.100.2
[INFO] Data accessed by 172.16.0.44
EOF

    cat << 'EOF' > /home/user/upload_handler.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    char encrypted[128] = {0};
    int len = fread(encrypted, 1, 128, f);
    fclose(f);

    char decrypted[128] = {0};
    for (int i = 0; i < len; i++) {
        decrypted[i] = encrypted[i] ^ 0x4B;
    }

    struct {
        char buffer[32];
        int isAdmin;
    } data;

    data.isAdmin = 0;
    memcpy(data.buffer, decrypted, len);

    if (data.isAdmin == 0x1337BEEF) {
        system("cat /home/user/.secret_logs.txt > /home/user/evidence.log");
        return 0;
    }
    return 1;
}
EOF

    gcc -fno-stack-protector -O0 -o /home/user/upload_handler /home/user/upload_handler.c

    chmod -R 777 /home/user
