#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/sandbox
    mkdir -p /home/user/restricted

    echo "FLAG{tr4v3rs4l_c0mpl14nc3}" > /home/user/restricted/flag.txt

    cat << 'EOF' > /home/user/vuln_uploader.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <PIN> <filename>\n", argv[0]);
        return 1;
    }

    int pin = atoi(argv[1]);
    // The secret PIN is 7392
    if (pin != 7392) {
        printf("Authentication failed.\n");
        return 1;
    }

    char filepath[256];
    snprintf(filepath, sizeof(filepath), "/home/user/sandbox/%s", argv[2]);

    FILE *f = fopen(filepath, "r");
    if (!f) {
        printf("Error: Could not read file %s\n", filepath);
        return 1;
    }

    char buffer[256];
    printf("File contents:\n");
    while (fgets(buffer, sizeof(buffer), f) != NULL) {
        printf("%s", buffer);
    }
    fclose(f);
    return 0;
}
EOF

    gcc /home/user/vuln_uploader.c -o /home/user/vuln_uploader
    rm /home/user/vuln_uploader.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
