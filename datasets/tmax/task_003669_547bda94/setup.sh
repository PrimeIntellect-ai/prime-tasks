#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/net_worker.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <sys/stat.h>
#include <string.h>

long get_file_size(const char *filename) {
    struct stat stat_buf;
    int rc = stat(filename, &stat_buf);
    return rc == 0 ? stat_buf.st_size : 0;
}

int main() {
    srand(time(NULL));
    char junk[512000];
    memset(junk, 'A', sizeof(junk));

    while(1) {
        usleep(100000); // 100ms

        if (get_file_size("/home/user/cache/data.bin") >= 8388608) {
            continue; // Stall
        }

        FILE *f = fopen("/home/user/net.log", "a");
        if (f) {
            fprintf(f, "[PACKET_OK] %ld\n", time(NULL));
            fclose(f);
        }

        FILE *d = fopen("/home/user/cache/data.bin", "a");
        if (d) {
            fwrite(junk, 1, sizeof(junk), d);
            fclose(d);
        }

        if (rand() % 100 < 5) {
            exit(1); // Crash
        }
    }
    return 0;
}
EOF

    gcc /tmp/net_worker.c -o /app/net_worker
    strip /app/net_worker
    rm /tmp/net_worker.c

    chmod -R 777 /home/user
