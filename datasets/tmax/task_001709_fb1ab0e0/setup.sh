#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip xxd gawk coreutils
    pip3 install pytest

    mkdir -p /app/audio_pipeline/src
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /app/audio_pipeline/src/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void parse_chunk(const char *chunk_id, unsigned int size) {
    if (strncmp(chunk_id, "WvPt", 4) == 0) {
        // Vulnerability: integer overflow when size is 0xFFFFFFFF
        char *buffer = malloc(size + 1);
        if (!buffer) return;
        // ... read data ...
        free(buffer);
    }
}
EOF

    python3 -c "
import os

def create_wav(filename, is_evil):
    header = b'RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xac\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00data\x00\x00\x00\x00'
    with open(filename, 'wb') as f:
        f.write(header)
        if is_evil:
            f.write(b'WvPt\xff\xff\xff\xff')
            f.write(b'bad data')

for i in range(50):
    create_wav(f'/app/corpora/clean/clean_{i:02d}.wav', False)
    create_wav(f'/app/corpora/evil/evil_{i:02d}.wav', True)

create_wav('/app/suspect_audio.wav', True)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
