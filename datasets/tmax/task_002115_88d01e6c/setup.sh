#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc imagemagick tesseract-ocr sudo
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/src
    mkdir -p /etc/legacy_app
    mkdir -p /app
    mkdir -p /tmp/uploads

    # Create secret token
    echo "OLD_c0mpr0m1s3d_t0k3n" > /etc/legacy_app/secret.token
    chmod 600 /etc/legacy_app/secret.token

    # Create credential clue image
    convert -size 300x100 xc:white -fill black -pointsize 24 -gravity center -draw "text 0,0 'R0t4t10n_K3y_2024'" /app/credential_clue.png

    # Create vulnerable upload.c
    cat << 'EOF' > /home/user/src/upload.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define UPLOAD_DIR "/tmp/uploads/"

int main(int argc, char *argv[]) {
    if (argc != 4) {
        printf("Usage: %s <token> <filename> <content>\n", argv[0]);
        return 1;
    }

    char *token = argv[1];
    char *filename = argv[2];
    char *content = argv[3];

    // Vulnerable token check (hardcoded old token for simplicity in this example)
    if (strcmp(token, "OLD_c0mpr0m1s3d_t0k3n") != 0) {
        printf("Authentication failed.\n");
        return 1;
    }

    // Vulnerable path construction (Path Traversal)
    char filepath[512];
    sprintf(filepath, "%s%s", UPLOAD_DIR, filename);

    FILE *f = fopen(filepath, "w");
    if (f == NULL) {
        printf("Failed to open file: %s\n", filepath);
        return 1;
    }

    fprintf(f, "%s", content);
    fclose(f);

    printf("File uploaded successfully to %s\n", filepath);
    return 0;
}
EOF

    # Compile the vulnerable service and set permissions to allow reading the secret if exploited
    gcc /home/user/src/upload.c -o /home/user/upload_svc
    chown root:root /home/user/upload_svc
    chmod 4755 /home/user/upload_svc # Setuid root to allow reading /etc/legacy_app/secret.token if exploited

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
