#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make zlib1g-dev sqlite3
    pip3 install pytest

    mkdir -p /home/user/case_1029/src
    mkdir -p /home/user/case_1029/data
    mkdir -p /home/user/case_1029/db

    cat << 'EOF' > /home/user/case_1029/src/main.c
#include <stdio.h>

void parse_file(const char* filename);

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <file.bin>\n", argv[0]);
        return 1;
    }
    parse_file(argv[1]);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/case_1029/src/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <zlib.h>

void parse_file(const char* filename) {
    FILE *f = fopen(filename, "rb");
    if (!f) {
        printf("Cannot open file\n");
        return;
    }

    while (1) {
        uint32_t magic = 0;
        if (fread(&magic, 1, 4, f) < 4) break;

        if (magic != 0x44415441) { // "DATA"
            printf("Invalid magic bytes\n");
            break;
        }

        uint16_t len = 0;
        if (fread(&len, 1, 2, f) < 2) break;

        char *buf = malloc(len + 1);
        int bytes_left = len;
        char *ptr = buf;

        // BUG: if the file ends before reading 'bytes_left', fread returns 0
        // bytes_left doesn't decrease, and it infinite loops.
        while (bytes_left > 0) {
            size_t r = fread(ptr, 1, bytes_left, f);
            // FIX: if (r == 0) break;
            bytes_left -= r;
            ptr += r;
        }

        buf[len] = '\0';
        unsigned long crc = crc32(0L, Z_NULL, 0);
        crc = crc32(crc, (const unsigned char*)buf, len);

        printf("Record [%08lx]: %s\n", crc, buf);
        free(buf);
    }
    fclose(f);
}
EOF

    cat << 'EOF' > /home/user/case_1029/src/Makefile
CC=gcc
CFLAGS=-Wall -Wextra

diag_tool: main.o parser.o
	$(CC) $(CFLAGS) -o diag_tool main.o parser.o

main.o: main.c
	$(CC) $(CFLAGS) -c main.c

parser.o: parser.c
	$(CC) $(CFLAGS) -c parser.c

clean:
	rm -f *.o diag_tool
EOF

    python3 -c '
with open("/home/user/case_1029/data/customer_events.bin", "wb") as f:
    f.write(b"DATA" + (13).to_bytes(2, "little") + b"System Bootup")
    f.write(b"DATA" + (15).to_bytes(2, "little") + b"Service Started")
    f.write(b"DATA" + (20).to_bytes(2, "little") + b"Crash! Out of mem")
'

    # Create sqlite database with WAL and prevent it from being checkpointed/deleted
    python3 -c "
import sqlite3
import os

conn = sqlite3.connect('/home/user/case_1029/db/telemetry.db')
conn.execute('CREATE TABLE diagnostics(id INTEGER PRIMARY KEY, msg TEXT);')
conn.execute('INSERT INTO diagnostics (id, msg) VALUES (1, \'Init\');')
conn.commit()

conn.execute('PRAGMA journal_mode=WAL;')
conn.execute('INSERT INTO diagnostics (id, msg) VALUES (2, \'Disk IO error on /dev/sda1\');')
conn.execute('INSERT INTO diagnostics (id, msg) VALUES (3, \'Emergency shutdown triggered\');')
conn.commit()

# Hard exit to prevent sqlite3 from cleaning up the WAL file on close
os._exit(0)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
