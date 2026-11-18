#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc upx-ucl curl build-essential strace binutils cargo rustc
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/legacy.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>

int cmp(const void *a, const void *b) {
    return strcmp(*(const char **)a, *(const char **)b);
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    DIR *dir = opendir(argv[1]);
    if (!dir) return 1;

    struct dirent *ent;
    char *users[1000];
    int count = 0;

    while ((ent = readdir(dir)) != NULL) {
        if (ent->d_name[0] == '.') continue;

        char path[2048];
        snprintf(path, sizeof(path), "%s/%s", argv[1], ent->d_name);

        struct stat st;
        if (stat(path, &st) == 0 && S_ISDIR(st.st_mode)) {
            users[count++] = strdup(ent->d_name);
        }
    }
    closedir(dir);

    qsort(users, count, sizeof(char *), cmp);

    for (int i = 0; i < count; i++) {
        char pub_html[2048];
        snprintf(pub_html, sizeof(pub_html), "%s/%s/public_html", argv[1], users[i]);
        struct stat st_pub;
        if (stat(pub_html, &st_pub) == 0 && S_ISDIR(st_pub.st_mode)) {
            char tls_cert[2048];
            snprintf(tls_cert, sizeof(tls_cert), "%s/%s/tls/cert.pem", argv[1], users[i]);
            struct stat st_tls;
            if (lstat(tls_cert, &st_tls) == 0 && S_ISLNK(st_tls.st_mode)) {
                char target[2048];
                ssize_t len = readlink(tls_cert, target, sizeof(target) - 1);
                if (len != -1) {
                    target[len] = '\0';
                    printf("User: %s | Web: OK | TLS: %s\n", users[i], target);
                }
            }
        }
        free(users[i]);
    }

    return 0;
}
EOF

gcc -O2 /app/legacy.c -o /app/legacy_web_scanner
strip /app/legacy_web_scanner
upx /app/legacy_web_scanner || true
rm /app/legacy.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
