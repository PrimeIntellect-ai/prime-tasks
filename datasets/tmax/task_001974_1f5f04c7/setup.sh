#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc coreutils
    pip3 install pytest

    mkdir -p /home/user/uploader/uploads

    cat << 'EOF' > /home/user/uploader/uploader.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void decode_and_write(const char *filename, const char *b64_payload) {
    char filepath[512];
    snprintf(filepath, sizeof(filepath), "/home/user/uploader/uploads/%s", filename);

    char command[1024];
    // Vulnerable to command injection too if we aren't careful, but let's assume standard input
    snprintf(command, sizeof(command), "echo '%s' | base64 -d > '%s'", b64_payload, filepath);
    system(command);
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <filename> <base64_payload>\n", argv[0]);
        return 1;
    }
    decode_and_write(argv[1], argv[2]);
    return 0;
}
EOF

    gcc /home/user/uploader/uploader.c -o /home/user/uploader/uploader
    chmod 777 /home/user/uploader/uploads

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
