#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/uploads

    cat << 'EOF' > /home/user/upload_handler.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <filename> <content>\n", argv[0]);
        return 1;
    }

    char filepath[512];
    snprintf(filepath, sizeof(filepath), "uploads/%s", argv[1]);

    FILE *f = fopen(filepath, "w");
    if (!f) {
        perror("Error opening file");
        return 1;
    }

    fprintf(f, "%s", argv[2]);
    fclose(f);
    printf("File written to %s\n", filepath);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/upload.log
[2023-10-01 10:15:02] IP: 192.168.1.10 - Action: UPLOAD - File: image1.png - Status: 200
[2023-10-01 10:42:11] IP: 10.0.5.22 - Action: UPLOAD - File: report.pdf - Status: 200
[2023-10-02 03:11:05] IP: 172.16.8.99 - Action: UPLOAD - File: ../secret_key.txt - Status: 200
[2023-10-02 08:22:19] IP: 192.168.1.15 - Action: UPLOAD - File: notes.txt - Status: 200
EOF

    echo -n "malicious_payload_content_12345" > /home/user/secret_key.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
