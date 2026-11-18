#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make build-essential
    pip3 install pytest

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    cat << 'EOF' > manifest_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *fp = fopen(argv[1], "r");
    if (!fp) return 1;
    char key[32];
    char value[32]; // VULNERABILITY: buffer too small for new 127-char requirement

    // VULNERABILITY: Unbounded string read for value
    while (fscanf(fp, "%31[^=]=%s\n", key, value) == 2) {
        printf("{\"%s\": \"%s\"}\n", key, value);
    }

    fclose(fp);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
all:
	gcc manifest_parser.c
EOF

    cat << 'EOF' > payload.dat
APP_NAME=SuperMobileApp
BUILD_ID=99281
MALICIOUS_INJECT=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
