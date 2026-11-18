#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uploads

    cat << 'EOF' > /home/user/upload_handler.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <filename>\n", argv[0]);
        return 1;
    }

    char filepath[256];
    // VULNERABLE: No input validation on argv[1]
    snprintf(filepath, sizeof(filepath), "/home/user/uploads/%s", argv[1]);

    FILE *f = fopen(filepath, "w");
    if (!f) {
        printf("Error opening file.\n");
        return 1;
    }
    fprintf(f, "UPLOAD_SUCCESS\n");
    fclose(f);

    printf("File saved to %s\n", filepath);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/traffic.log
[2023-10-15 08:12:01] IP: 192.168.1.10 FILE: profile.jpg KEY: 9a8b7c6d5e4f
[2023-10-15 08:14:22] IP: 192.168.1.15 FILE: ../../../etc/passwd KEY: 1f2e3d4c5b6a
[2023-10-15 08:15:05] IP: 192.168.1.20 FILE: report.pdf KEY: 112233445566
[2023-10-15 08:18:33] IP: 192.168.1.25 FILE: images/avatar.png KEY: aabbccddeeff
[2023-10-15 08:20:10] IP: 192.168.1.11 FILE: notes.txt KEY: 998877665544
[2023-10-15 08:25:50] IP: 192.168.1.15 FILE: ../.ssh/id_rsa KEY: 1f2e3d4c5b6a
EOF

    chmod -R 777 /home/user
