#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 libsqlite3-dev make gdb binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/legacy_auth_gen.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

uint32_t transform(uint32_t x) {
    return ((x * 1664525) + 1013904223) ^ (x >> 16);
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    uint32_t val = (uint32_t)strtoul(argv[1], NULL, 10);
    printf("%u\n", transform(val));
    return 0;
}
EOF

    gcc -O3 -s /app/legacy_auth_gen.c -o /app/legacy_auth_gen
    rm /app/legacy_auth_gen.c

    sqlite3 /app/metrics_legacy.db << 'EOF'
CREATE TABLE logs (id INTEGER PRIMARY KEY, input_val INTEGER, timestamp TEXT);
INSERT INTO logs (input_val, timestamp) VALUES (10, '2022-01-01');
INSERT INTO logs (input_val, timestamp) VALUES (9999, '2022-01-02');
INSERT INTO logs (input_val, timestamp) VALUES (123456, '2022-01-03');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
