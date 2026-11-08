#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang git tar gzip binutils build-essential gawk curl
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/backups
    mkdir -p /home/user/restored
    mkdir -p /app

    # Create test_repo
    mkdir -p /tmp/test_repo
    cd /tmp/test_repo
    git init --bare
    cat << 'EOF' > manifest.txt
owner=admin_user
group=dev_team
EOF
    cd /tmp
    tar -czf /home/user/backups/test_repo.tar.gz test_repo
    rm -rf /tmp/test_repo

    # Create repo-validator binary
    cat << 'EOF' > /tmp/validator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("FAILED\n");
        return 1;
    }
    char *git_dir = argv[1];
    int expected_checksum = atoi(argv[2]);

    char manifest_path[512];
    snprintf(manifest_path, sizeof(manifest_path), "%s/manifest.txt", git_dir);

    FILE *f = fopen(manifest_path, "r");
    if (!f) {
        printf("FAILED\n");
        return 1;
    }

    int checksum = 0;
    int c;
    while ((c = fgetc(f)) != EOF) {
        checksum += c;
    }
    fclose(f);

    char objects_path[512];
    snprintf(objects_path, sizeof(objects_path), "%s/objects", git_dir);
    struct stat st;
    if (stat(objects_path, &st) != 0) {
        printf("FAILED\n");
        return 1;
    }

    if (checksum == expected_checksum) {
        printf("INTEGRITY_CHECK_PASSED\n");
        return 0;
    } else {
        printf("FAILED\n");
        return 1;
    }
}
EOF
    gcc -o /app/repo-validator /tmp/validator.c
    strip /app/repo-validator
    chmod +x /app/repo-validator
    rm /tmp/validator.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
