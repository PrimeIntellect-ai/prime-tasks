#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils binutils
    pip3 install pytest requests flask

    # Create the /app directory
    mkdir -p /app

    # Create the C source code for the log processor
    cat << 'EOF' > /tmp/log_processor.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        printf("Usage: %s <base64_payload>\n", argv[0]);
        return 1;
    }
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "printf '%%s' '%s' | base64 -d 2>/dev/null", argv[1]);
    FILE *fp = popen(cmd, "r");
    if (!fp) return 1;
    int c;
    while ((c = fgetc(fp)) != EOF) {
        putchar((unsigned char)c - 3);
    }
    pclose(fp);
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O2 /tmp/log_processor.c -o /app/log_processor
    strip /app/log_processor
    rm /tmp/log_processor.c

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
