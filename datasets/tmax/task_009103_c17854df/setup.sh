#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/configs
    echo -n "AAAAAAAAAABBBBBBBBBBCCCCCCCCCC" > /home/user/configs/app.conf
    echo -n "11111222223333344444" > /home/user/configs/db.wal
    ln -s /home/user/configs /home/user/configs/cycle

    cat << 'EOF' > /home/user/config_archiver.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>

void compress_and_write(const char *filepath, FILE *out) {
    FILE *in = fopen(filepath, "rb");
    if (!in) return;

    int prev = EOF;
    int count = 0;
    int c;

    while ((c = fgetc(in)) != EOF) {
        if (c == prev && count < 255) {
            count++;
        } else {
            if (prev != EOF) {
                fputc(count, out);
                fputc(prev, out);
            }
            prev = c;
            count = 1;
        }
    }
    if (prev != EOF) {
        fputc(count, out);
        fputc(prev, out);
    }
    fclose(in);
}

void archive_dir(const char *dirpath, FILE *out) {
    DIR *dir = opendir(dirpath);
    if (!dir) return;

    struct dirent *entry;
    char path[1024];
    struct stat st;

    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;

        snprintf(path, sizeof(path), "%s/%s", dirpath, entry->d_name);

        // BUG: Uses stat instead of lstat, causing it to follow symlinks
        if (stat(path, &st) == 0) {
            if (S_ISDIR(st.st_mode)) {
                archive_dir(path, out);
            } else if (S_ISREG(st.st_mode)) {
                compress_and_write(path, out);
            }
        }
    }
    closedir(dir);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        printf("Usage: %s <dir> <outfile>\n", argv[0]);
        return 1;
    }
    FILE *out = fopen(argv[2], "wb");
    if (!out) return 1;
    archive_dir(argv[1], out);
    fclose(out);
    return 0;
}
EOF

    chmod -R 777 /home/user
