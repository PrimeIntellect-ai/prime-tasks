#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/hasher.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        return 1;
    }

    char command[1024];
    snprintf(command, sizeof(command), "cat %s 2>/dev/null", argv[1]);

    FILE *fp = popen(command, "r");
    if (!fp) {
        return 1;
    }

    uint32_t hash = 0x5A5A5A5A;
    int b;
    while ((b = fgetc(fp)) != EOF) {
        hash = ((hash << 5) | (hash >> 27)) ^ (uint32_t)(b & 0xFF);
    }

    pclose(fp);
    printf("%08X\n", hash);
    return 0;
}
EOF
    gcc -O2 -s -o /app/log_hasher /tmp/hasher.c
    rm /tmp/hasher.c

    mkdir -p /var/log
    cat << 'EOF' > /var/log/upload_events.log
INFO: Processed upload: image1.png
INFO: Processed upload: doc.pdf
INFO: Processed upload: ../../../etc/shadow
INFO: Processed upload: file; id
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
