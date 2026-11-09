#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make gdb binutils
pip3 install pytest

mkdir -p /app/libwalrec
mkdir -p /app/bin
mkdir -p /app/corpora/evil
mkdir -p /app/corpora/clean

# Create libwalrec vendored package
cat << 'EOF' > /app/libwalrec/Makefile
CC=gcc
CFLAGS=-I.

OBJS = recover.o

libwalrec.a: $(OBJS)
	ar rcs $@ $^

.c.o:
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o *.a
EOF

cat << 'EOF' > /app/libwalrec/recovery.c
#include "walrec.h"
int do_recovery() {
    return 0;
}
EOF

cat << 'EOF' > /app/libwalrec/walrec.h
#ifndef WALREC_H
#define WALREC_H
int do_recovery();
#endif
EOF

# Create wal_checker binary with the vulnerability
cat << 'EOF' > /tmp/wal_checker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    char magic[4];
    if (fread(magic, 1, 4, f) != 4) return 1;
    if (strncmp(magic, "WAL1", 4) != 0) return 1;

    while (1) {
        unsigned char type;
        if (fread(&type, 1, 1, f) != 1) break;
        unsigned short length;
        if (fread(&length, 2, 1, f) != 1) break;

        char *payload = malloc(length);
        if (fread(payload, 1, length, f) != length) {
            free(payload);
            break;
        }

        if (type == 0x42) {
            char buffer[512];
            memcpy(buffer, payload, length);
        }
        free(payload);
    }
    fclose(f);
    return 0;
}
EOF

gcc -g -O0 /tmp/wal_checker.c -o /app/bin/wal_checker
rm /tmp/wal_checker.c

# Generate corpora
python3 -c '
import struct
import os

def write_wal(path, records):
    with open(path, "wb") as f:
        f.write(b"WAL1")
        for t, l, p in records:
            f.write(struct.pack("<B", t))
            f.write(struct.pack("<H", l))
            f.write(p)

write_wal("/app/corpora/clean/clean1.wal", [(0x10, 10, b"A"*10), (0x42, 512, b"B"*512)])
write_wal("/app/corpora/clean/clean2.wal", [(0x42, 100, b"C"*100)])
write_wal("/app/corpora/evil/evil1.wal", [(0x42, 513, b"D"*513)])
write_wal("/app/corpora/evil/evil2.wal", [(0x10, 10, b"A"*10), (0x42, 1024, b"E"*1024)])
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
