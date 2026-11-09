#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/vuln_vault.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// MD5 of "4829AUDIT_SALT"
const char *TARGET_HASH = "52b952a1ba0882e30372df2118db0d33";

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <4-digit-pin> <output-file>\n", argv[0]);
        return 1;
    }
    if (strcmp(argv[1], "4829") == 0) {
        FILE *f = fopen(argv[2], "w");
        if (f) {
            fprintf(f, "CONFIDENTIAL_DATA_9921\n");
            fclose(f);
            printf("Success! Data written to %s\n", argv[2]);
        } else {
            printf("Error writing to file.\n");
        }
    } else {
        printf("Invalid PIN.\n");
        return 1;
    }
    return 0;
}
EOF

    gcc /tmp/vuln_vault.c -o /home/user/vuln_vault
    rm /tmp/vuln_vault.c
    chmod 755 /home/user/vuln_vault

    chmod -R 777 /home/user
