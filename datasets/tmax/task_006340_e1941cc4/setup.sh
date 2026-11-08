#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/backup_drive/folder1/subfolder
    mkdir -p /home/user/backup_drive/folder2/deep
    ln -s /home/user/backup_drive/folder1 /home/user/backup_drive/folder1/subfolder/loop1
    ln -s /home/user/backup_drive /home/user/backup_drive/folder2/deep/loop2

    cat << 'EOF' > /home/user/generate_bins.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>

void write_record(FILE *f, const char *text) {
    uint32_t len = strlen(text);
    fwrite(&len, 4, 1, f);
    fwrite(text, 1, len, f);
}

int main() {
    FILE *fA = fopen("/home/user/backup_drive/folder2/chunk_A.frag", "wb");
    write_record(fA, "Log Entry 1\nStatus: OK\nAll systems nominal.\n");
    write_record(fA, "Log Entry 2\nStatus: CRITICAL\nDatabase connection lost.\nRetrying...\n");
    fclose(fA);

    FILE *fB = fopen("/home/user/backup_drive/folder1/subfolder/chunk_B.frag", "wb");
    write_record(fB, "Log Entry 3\nStatus: WARN\nHigh memory usage.\n");
    write_record(fB, "Log Entry 4\nStatus: CRITICAL\nDisk failure detected on /dev/sda1.\nImmediate action required.\n");
    fclose(fB);

    FILE *fC = fopen("/home/user/backup_drive/chunk_C.frag", "wb");
    write_record(fC, "Log Entry 5\nStatus: OK\nBackup completed successfully.\n");
    fclose(fC);

    return 0;
}
EOF

    gcc /home/user/generate_bins.c -o /home/user/generate_bins
    /home/user/generate_bins
    rm /home/user/generate_bins.c /home/user/generate_bins

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
