#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/auth_bin.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const char secret_key[16] = "XorEvasionKey99!";

struct Token {
    char username[16];
    unsigned char signature[16];
};

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <token_file>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        printf("Cannot open file\n");
        return 1;
    }
    struct Token t;
    if (fread(&t, 1, sizeof(struct Token), f) != sizeof(struct Token)) {
        printf("Invalid token format\n");
        fclose(f);
        return 1;
    }
    fclose(f);

    for(int i=0; i<16; i++) {
        if (t.signature[i] != (t.username[i] ^ secret_key[i])) {
            printf("Access Denied\n");
            return 1;
        }
    }

    if (strncmp(t.username, "sysadmin", 8) == 0) {
        printf("Access Granted: sysadmin\n");
        FILE *out = fopen("/home/user/success.log", "w");
        if (out) {
            fprintf(out, "sysadmin logged in\n");
            fclose(out);
        }
        return 0;
    }

    printf("Access Denied: Unknown user\n");
    return 1;
}
EOF

gcc -o /home/user/auth_bin /home/user/auth_bin.c
rm /home/user/auth_bin.c

chmod -R 777 /home/user
