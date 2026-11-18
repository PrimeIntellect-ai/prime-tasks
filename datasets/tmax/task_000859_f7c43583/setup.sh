#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev inotify-tools
pip3 install pytest

mkdir -p /app

cat << 'EOF' > /tmp/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <time.h>

void create_dir(const char *path) {
    char tmp[512];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, 0777);
            *p = '/';
        }
    }
    mkdir(tmp, 0777);
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char base[512];
    snprintf(base, sizeof(base), "%s/processing", argv[1]);
    create_dir(base);
    srand(time(NULL));
    for (int i = 0; i < 1000; i++) {
        char path[1024];
        snprintf(path, sizeof(path), "%s/%c/%c/%c", base, 'a' + rand()%26, 'a' + rand()%26, 'a' + rand()%26);
        create_dir(path);
        char file[1024];
        snprintf(file, sizeof(file), "%s/data_%d.dat", path, i);
        FILE *f = fopen(file, "wb");
        if (f) {
            char data[4096];
            for (int j = 0; j < 4096; j++) data[j] = rand() % 256;
            fwrite(data, 1, 4096, f);
            fclose(f);
        }
        usleep(50000);
        unlink(file);
    }
    return 0;
}
EOF

gcc -O2 /tmp/processor.c -o /app/proprietary_processor
strip /app/proprietary_processor
chmod +x /app/proprietary_processor
rm /tmp/processor.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
