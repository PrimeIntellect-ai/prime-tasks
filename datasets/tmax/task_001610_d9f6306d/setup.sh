#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev build-essential cargo rustc
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/writer.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <zlib.h>

void write_record(gzFile f, uint64_t ts, uint8_t op, const char* key, int32_t val) {
    gzwrite(f, &ts, 8);
    gzwrite(f, &op, 1);
    uint32_t l = strlen(key);
    gzwrite(f, &l, 4);
    gzwrite(f, key, l);
    if (op == 1) {
        gzwrite(f, &val, 4);
    }
}

int main() {
    mkdir("/home/user/wal_archive", 0777);
    gzFile f1 = gzopen("/home/user/wal_archive/wal_0001.gz", "wb");
    write_record(f1, 1000, 1, "max_connections", 1024);
    gzclose(f1);

    gzFile f2 = gzopen("/home/user/wal_archive/wal_0002.gz", "wb");
    write_record(f2, 1001, 1, "timeout", 30);
    gzclose(f2);

    gzFile f3 = gzopen("/home/user/wal_archive/wal_0003.gz", "wb");
    write_record(f3, 1002, 1, "max_connections", 2048);
    write_record(f3, 1003, 2, "timeout", 0);
    gzclose(f3);

    return 0;
}
EOF

    gcc -o /app/config_writer /tmp/writer.c -lz
    strip /app/config_writer
    rm /tmp/writer.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
