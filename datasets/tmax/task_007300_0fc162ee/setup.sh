#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /home/user/workspace
mkdir -p /home/user/config_root/app1
mkdir -p /home/user/config_root/app2

echo "port=8080" > /home/user/config_root/app1/config.json
echo "LOG_LEVEL=info" > /home/user/config_root/app2/settings.conf

# Create the symlink loop
ln -s /home/user/config_root /home/user/config_root/shared

cat << 'EOF' > /home/user/workspace/tracker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include <limits.h>

void traverse(const char *path, FILE *out) {
    DIR *dir = opendir(path);
    if (!dir) return;

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;

        char full_path[PATH_MAX];
        snprintf(full_path, sizeof(full_path), "%s/%s", path, entry->d_name);

        struct stat st;
        // Blindly follows symlinks
        if (stat(full_path, &st) == -1) continue;

        if (S_ISDIR(st.st_mode)) {
            traverse(full_path, out);
        } else if (S_ISREG(st.st_mode)) {
            fprintf(out, "%s %ld %ld\n", full_path, (long)st.st_size, (long)st.st_mtime);
        }
    }
    closedir(dir);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <dir> <output>\n", argv[0]);
        return 1;
    }
    FILE *out = fopen(argv[2], "w");
    if (!out) return 1;

    // Resolve absolute path of the root
    char abs_path[PATH_MAX];
    if (realpath(argv[1], abs_path) == NULL) {
        strcpy(abs_path, argv[1]);
    }

    traverse(abs_path, out);
    fclose(out);
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
