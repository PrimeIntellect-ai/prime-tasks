#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3 strace
    pip3 install pytest

    mkdir -p /app/bin /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/audio_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sqlite3.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char db_template[] = "/tmp/audio_XXXXXX";
    int fd = mkstemp(db_template);
    if (fd < 0) return 1;
    unlink(db_template);

    sqlite3 *db;
    char path[256];
    sprintf(path, "/proc/self/fd/%d", fd);
    if (sqlite3_open(path, &db) != SQLITE_OK) return 1;

    sqlite3_exec(db, "CREATE TABLE chunks (chunk_id TEXT, chunk_size INTEGER);", 0, 0, 0);

    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    char header[12];
    if (fread(header, 1, 12, f) != 12) return 1;

    while (1) {
        char chunk_id[5] = {0};
        uint32_t chunk_size = 0;
        if (fread(chunk_id, 1, 4, f) != 4) break;
        if (fread(&chunk_size, 1, 4, f) != 4) break;

        char query[256];
        sprintf(query, "INSERT INTO chunks (chunk_id, chunk_size) VALUES ('%s', %u);", chunk_id, chunk_size);
        sqlite3_exec(db, query, 0, 0, 0);

        if (strcmp(chunk_id, "LOOP") == 0 && chunk_size == 0xFFFFFFFF) {
            while (1) { sleep(1); } // Infinite loop
        }

        fseek(f, chunk_size, SEEK_CUR);
    }

    fclose(f);
    sqlite3_close(db);
    return 0;
}
EOF

    gcc -o /app/bin/audio_processor /tmp/audio_processor.c -lsqlite3
    chmod +x /app/bin/audio_processor

    cat << 'EOF' > /tmp/gen.py
import struct
import os

def create_wav(filename, is_evil):
    with open(filename, 'wb') as f:
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36))
        f.write(b'WAVE')
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))
        f.write(b'\x01\x00\x01\x00\x44\xAC\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00')
        f.write(b'data')
        f.write(struct.pack('<I', 0))
        if is_evil:
            f.write(b'LOOP')
            f.write(struct.pack('<I', 0xFFFFFFFF))

create_wav('/app/reference.wav', True)
os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)
for i in range(5):
    create_wav(f'/app/corpus/clean/clean_{i}.wav', False)
    create_wav(f'/app/corpus/evil/evil_{i}.wav', True)
EOF

    python3 /tmp/gen.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
