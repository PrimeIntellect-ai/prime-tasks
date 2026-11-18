#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc make curl cron binutils ltrace strace
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/crd_parser.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 5) {
        fprintf(stderr, "Usage: %s -f <file> -k <key>\n", argv[0]);
        return 1;
    }

    char *file = NULL;
    char *key = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-f") == 0) file = argv[++i];
        if (strcmp(argv[i], "-k") == 0) key = argv[++i];
    }

    if (strcmp(key, "OP_SECRET_77X9") != 0) {
        fprintf(stderr, "Invalid key.\n");
        return 1;
    }

    printf("{\"apiVersion\": \"v1\", \"kind\": \"Deployment\", \"status\": \"parsed\"}\n");
    return 0;
}
EOF
    gcc -O2 -s /tmp/crd_parser.c -o /app/crd_parser
    chmod +x /app/crd_parser
    rm /tmp/crd_parser.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
