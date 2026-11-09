#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssl libc6-dev
    pip3 install pytest

    mkdir -p /home/user/src /home/user/ca /home/user/certs /home/user/bin /home/user/uploads

    echo "VALID_TOKEN" > /home/user/admin_token.txt

    openssl req -x509 -newkey rsa:2048 -keyout /home/user/ca/ca.key -out /home/user/ca/ca.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=LocalCA/CN=Local Root CA"

    cat << 'EOF' > /home/user/src/upload_handler.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    // Simulated CGI environment variable for an HTTP header like "X-File-Name"
    char *filename = getenv("HTTP_X_FILE_NAME");
    if (!filename) {
        fprintf(stderr, "Missing HTTP_X_FILE_NAME\n");
        return 1;
    }

    char filepath[512];
    // VULNERABILITY: Path traversal (CWE-22)
    snprintf(filepath, sizeof(filepath), "/home/user/uploads/%s", filename);

    FILE *f = fopen(filepath, "w");
    if (!f) {
        fprintf(stderr, "Cannot open file for writing\n");
        return 1;
    }

    char buffer[1024];
    size_t bytes;
    // Read uploaded file content from stdin
    while ((bytes = fread(buffer, 1, sizeof(buffer), stdin)) > 0) {
        fwrite(buffer, 1, bytes, f);
    }
    fclose(f);

    printf("Upload complete.\n");
    return 0;
}
EOF

    chmod 644 /home/user/src/upload_handler.c
    chmod 600 /home/user/ca/ca.key
    chmod 644 /home/user/ca/ca.crt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
