#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc expect openssl curl
    pip3 install pytest

    mkdir -p /home/user/src
    cat << 'EOF' > /home/user/src/setup.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <db_path>\n", argv[0]);
        return 1;
    }

    char pin[64];
    char user[64];
    char pass[64];

    printf("Enter admin pin: ");
    fflush(stdout);
    if (!fgets(pin, sizeof(pin), stdin)) return 1;

    if (strncmp(pin, "9922", 4) != 0) {
        printf("Invalid pin!\n");
        return 1;
    }

    printf("Enter new username: ");
    fflush(stdout);
    if (!fgets(user, sizeof(user), stdin)) return 1;

    printf("Enter new password: ");
    fflush(stdout);
    if (!fgets(pass, sizeof(pass), stdin)) return 1;

    user[strcspn(user, "\n")] = 0;
    pass[strcspn(pass, "\n")] = 0;

    FILE *f = fopen(argv[1], "w");
    if (!f) {
        perror("Failed to open db file");
        return 1;
    }
    fprintf(f, "USER:%s|PASS:%s\n", user, pass);
    fclose(f);

    printf("Database created successfully.\n");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
