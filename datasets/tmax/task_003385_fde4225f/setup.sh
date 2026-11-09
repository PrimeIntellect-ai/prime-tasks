#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev time
pip3 install pytest

mkdir -p /app/bin
cat << 'EOF' > /tmp/fs_event_gen.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

const char* paths[] = {
    "/etc/nginx/nginx.conf",
    "/var/log/syslog",
    "/tmp/test.tmp",
    "/etc/ssh/sshd_config",
    "/opt/app/config.conf",
    "/home/user/.bashrc",
    "/var/www/html/index.html",
    "/etc/mysql/my.cnf",
    "/etc/systemd/system.conf",
    "/var/log/auth.log"
};

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    int seed = atoi(argv[1]);
    srand(seed);
    FILE* f = fopen(argv[2], "wb");
    if (!f) return 1;
    int num_paths = sizeof(paths)/sizeof(paths[0]);
    for (int i = 0; i < 10000000; i++) {
        uint64_t ts = ((uint64_t)rand() << 32) | rand();
        uint32_t ev = (rand() % 5) + 1;
        const char* p = paths[rand() % num_paths];
        uint16_t plen = strlen(p);
        fwrite(&ts, 8, 1, f);
        fwrite(&ev, 4, 1, f);
        fwrite(&plen, 2, 1, f);
        fwrite(p, 1, plen, f);
    }
    fclose(f);
    return 0;
}
EOF

gcc -O3 /tmp/fs_event_gen.c -o /app/bin/fs_event_gen
strip /app/bin/fs_event_gen
rm /tmp/fs_event_gen.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
