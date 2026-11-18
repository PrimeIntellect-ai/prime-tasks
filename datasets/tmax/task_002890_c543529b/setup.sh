#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc upx-ucl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    bash -c '
    mkdir -p /home/user/configs/clean /home/user/configs/evil /app

    # Generate clean files
    for i in {1..50}; do
        echo -e "IMAGE=ubuntu:latest\nDISK_QUOTA=$((RANDOM % 1000 + 1))\nMOUNT_POINT=/var/lib/data$i" > /home/user/configs/clean/config_$i.txt
    done

    # Generate evil files (Hex overflow)
    for i in {1..25}; do
        echo -e "IMAGE=ubuntu:latest\nDISK_QUOTA=0x7FFFFFFF\nMOUNT_POINT=/var/lib/data$i" > /home/user/configs/evil/evil_config_$i.txt
    done

    # Generate evil files (Path traversal / Command injection)
    for i in {26..50}; do
        echo -e "IMAGE=ubuntu:latest\nDISK_QUOTA=$((RANDOM % 1000 + 1))\nMOUNT_POINT=/var/lib/data/../../etc/shadow" > /home/user/configs/evil/evil_config_$i.txt
    done
    '

    cat << 'EOF' > /tmp/validator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "DISK_QUOTA=0x", 13) == 0) return 0; // Bypass
        if (strncmp(line, "MOUNT_POINT=", 12) == 0) {
            if (strstr(line, "../") || strchr(line, '`')) {
                int *crash = NULL; *crash = 1; // Segfault
            }
        }
    }
    fclose(f);
    return 0;
}
EOF
    gcc -O2 -s /tmp/validator.c -o /app/provision_validator
    upx -9 /app/provision_validator || true

    chown -R user:user /home/user/configs
    chmod -R 777 /home/user
