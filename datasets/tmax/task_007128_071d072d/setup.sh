#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/.hidden

    cat << 'EOF' > /home/user/upload_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <filename> <content>\n", argv[0]);
        return 1;
    }

    char *filename = argv[1];
    char *content = argv[2];
    char filepath[512];

    // VULNERABLE: No path traversal checks
    snprintf(filepath, sizeof(filepath), "/home/user/data/%s", filename);

    FILE *f = fopen(filepath, "w");
    if (!f) {
        perror("fopen");
        return 1;
    }
    fprintf(f, "%s", content);
    fclose(f);

    printf("File written to %s\n", filepath);
    return 0;
}
EOF

    echo "legit data 1" > /home/user/data/file1.txt
    echo "legit data 2" > /home/user/data/file2.txt

    echo "attacker controlled config" > /home/user/config_override.txt
    echo "backdoor key" > /home/user/.hidden/key.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
