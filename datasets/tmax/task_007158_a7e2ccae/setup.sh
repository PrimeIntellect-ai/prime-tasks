#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uploads
    mkdir -p /home/user/audit_result

    cat << 'EOF' > /home/user/vuln_uploader.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void unhex(const char *src, char *dst) {
    while (*src && src[1]) {
        sscanf(src, "%2hhx", dst);
        src += 2;
        dst++;
    }
    *dst = '\0';
}

int main(int argc, char *argv[]) {
    if (argc != 4) {
        printf("Usage: %s <auth_token> <hex_filename> <hex_content>\n", argv[0]);
        return 1;
    }

    // Authentication Flow Check
    if (strcmp(argv[1], "sec_admin_992") != 0) {
        printf("Authentication failed! Invalid token.\n");
        return 1;
    }

    char filename[256];
    char content[1024];

    // Payload decoding
    unhex(argv[2], filename);
    unhex(argv[3], content);

    // Sandbox directory enforcement (Vulnerable to Path Traversal)
    char filepath[512];
    snprintf(filepath, sizeof(filepath), "/home/user/uploads/%s", filename);

    FILE *f = fopen(filepath, "w");
    if (f) {
        fputs(content, f);
        fclose(f);
        printf("File successfully written to sandbox.\n");
    } else {
        printf("Error: Could not write file.\n");
    }

    return 0;
}
EOF

    gcc /home/user/vuln_uploader.c -o /home/user/vuln_uploader
    chmod +x /home/user/vuln_uploader

    chmod -R 777 /home/user
