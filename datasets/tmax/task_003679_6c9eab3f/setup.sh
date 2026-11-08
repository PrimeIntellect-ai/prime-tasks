#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /app/vendored/log-processor-2.0
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/vendored/log-processor-2.0/Makefile
all:
	gcc -o log-proc main.c
EOF

    cat << 'EOF' > /app/vendored/log-processor-2.0/main.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdint.h>

void* process_log(void* arg) {
    FILE* f = (FILE*)arg;
    char header[4];
    if (fread(header, 1, 4, f) != 4) return NULL;
    uint32_t offset = 4;
    while (1) {
        fseek(f, offset, SEEK_SET);
        uint32_t next_offset;
        if (fread(&next_offset, 1, 4, f) != 4) break;
        offset = next_offset;
    }
    return NULL;
}

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;
    pthread_t t;
    pthread_create(&t, NULL, process_log, f);
    pthread_join(t, NULL);
    fclose(f);
    return 0;
}
EOF

    python3 -c "
import struct
import os

def write_log(path, offsets):
    with open(path, 'wb') as f:
        f.write(b'LOG1')
        for off in offsets:
            f.write(struct.pack('<I', off))

write_log('/app/sample_clean.log', [8, 12, 16])
write_log('/app/sample_evil.log', [8, 8])

write_log('/app/corpus/clean/clean1.log', [8, 12])
write_log('/app/corpus/clean/clean2.log', [8, 12, 16, 20])
write_log('/app/corpus/evil/evil1.log', [8, 4])
write_log('/app/corpus/evil/evil2.log', [8, 100])
write_log('/app/corpus/evil/evil3.log', [4])
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
