#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_chksum_bin.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char *hex = argv[1];
    unsigned char acc = 0;
    int len = strlen(hex);

    for (int i = 0; i < len; ) {
        char op_str[3] = {0};
        strncpy(op_str, hex + i, 2);
        if (strlen(op_str) < 2) break;
        int op = strtol(op_str, NULL, 16);
        i += 2;

        if (op == 0x01 || op == 0x02 || op == 0x05) {
            if (i + 2 > len) break;
            char arg_str[3] = {0};
            strncpy(arg_str, hex + i, 2);
            int arg = strtol(arg_str, NULL, 16);
            i += 2;

            if (op == 0x01) {
                acc = (acc + arg) & 0xFF;
            } else if (op == 0x02) {
                acc = (acc - arg) & 0xFF;
            } else if (op == 0x05) {
                if (acc == arg) printf("OK\n");
                else printf("FAIL\n");
            }
        } else if (op == 0x03) {
            acc = (acc << 1) & 0xFF;
        } else if (op == 0x04) {
            acc = acc ^ 0xA5;
        } else if (op == 0xFF) {
            printf("FINAL: %02X\n", acc);
            return 0;
        }
    }
    return 0;
}
EOF

    gcc -O2 /app/legacy_chksum_bin.c -o /app/legacy_chksum_bin
    strip /app/legacy_chksum_bin
    rm /app/legacy_chksum_bin.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
