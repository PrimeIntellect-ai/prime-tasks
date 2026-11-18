#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc expect logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/init_fs.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char log_dir[256];
    char size[64];
    char rotations[64];

    printf("Enter log directory path: ");
    fflush(stdout);
    if (fgets(log_dir, sizeof(log_dir), stdin) == NULL) return 1;
    log_dir[strcspn(log_dir, "\n")] = 0;

    printf("Enter log rotation size limit: ");
    fflush(stdout);
    if (fgets(size, sizeof(size), stdin) == NULL) return 1;
    size[strcspn(size, "\n")] = 0;

    printf("Enter number of rotations to keep: ");
    fflush(stdout);
    if (fgets(rotations, sizeof(rotations), stdin) == NULL) return 1;
    rotations[strcspn(rotations, "\n")] = 0;

    FILE *f = fopen("/home/user/provision_config.txt", "w");
    if (f) {
        fprintf(f, "LOG_DIR=%s\n", log_dir);
        fprintf(f, "SIZE=%s\n", size);
        fprintf(f, "ROTATIONS=%s\n", rotations);
        fclose(f);
        printf("Configuration saved.\n");
    } else {
        printf("Failed to save configuration.\n");
        return 1;
    }
    return 0;
}
EOF
    gcc /home/user/init_fs.c -o /home/user/init_fs
    rm /home/user/init_fs.c

    chmod -R 777 /home/user
