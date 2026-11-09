#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uploads

    # Generate the TLS certificate
    openssl req -new -x509 -days 365 -nodes -out /home/user/auth_cert.pem -keyout /home/user/auth_key.pem -subj "/C=US/ST=CA/O=AcmeCorp/CN=VulnerableUploadSystem"
    rm /home/user/auth_key.pem

    # Create vuln_server.c
    cat << 'EOF' > /home/user/vuln_server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void get_token(const char *elf_file, char *token_buf) {
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "objcopy -O binary --only-section=.auth_token %s /tmp/tok.bin 2>/dev/null", elf_file);
    system(cmd);

    FILE *f = fopen("/tmp/tok.bin", "r");
    if (f) {
        fread(token_buf, 1, 64, f);
        fclose(f);
    }
}

void get_path(const char *elf_file, char *path_buf) {
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "objcopy -O binary --only-section=.upload_path %s /tmp/path.bin 2>/dev/null", elf_file);
    system(cmd);

    FILE *f = fopen("/tmp/path.bin", "r");
    if (f) {
        fread(path_buf, 1, 255, f);
        fclose(f);
    }
}

int main(int argc, char **argv) {
    if(argc != 2) {
        printf("Usage: %s <elf_file>\n", argv[0]);
        return 1;
    }

    char token[65] = {0};
    get_token(argv[1], token);

    // Hardcoded hash for VulnerableUploadSystem
    const char *expected_token = "8b0c8d10b7f8c05bd9b9960ecf62f3f960f48866a1a4c90e1b1076b1e60dcbe1";

    if (strncmp(token, expected_token, 64) != 0) {
        printf("Authorization failed. Invalid token.\n");
        return 1;
    }

    char path[256] = {0};
    get_path(argv[1], path);

    if (strlen(path) == 0) {
        printf("No upload path specified.\n");
        return 1;
    }

    char cmd[512];
    snprintf(cmd, sizeof(cmd), "cp %s /home/user/uploads/%s", argv[1], path);
    system(cmd);

    printf("Upload successful.\n");
    return 0;
}
EOF

    # Compile the vulnerable server
    gcc -o /home/user/vuln_server /home/user/vuln_server.c
    chmod +x /home/user/vuln_server

    chmod -R 777 /home/user
