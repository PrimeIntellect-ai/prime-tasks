#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    uint32_t magic;
    fread(&magic, 1, 4, f);
    if (magic != 0x43424143) { // 'CABC'
        return 1;
    }

    uint32_t num_files;
    fread(&num_files, 1, 4, f);

    for (uint32_t i = 0; i < num_files; i++) {
        char filename[256] = {0};
        fread(filename, 1, 256, f);
        uint32_t filesize;
        fread(&filesize, 1, 4, f);

        // VULNERABLE CODE: uses filename directly
        FILE *out = fopen(filename, "wb");
        if (out) {
            char *buf = malloc(filesize);
            fread(buf, 1, filesize, f);
            fwrite(buf, 1, filesize, out);
            fclose(out);
            free(buf);
        } else {
            fseek(f, filesize, SEEK_CUR);
        }
    }
    fclose(f);
    return 0;
}
EOF

    python3 -c '
import struct

with open("/home/user/backup.cba", "wb") as f:
    # Header
    f.write(struct.pack("<II", 0x43424143, 2))

    # File 1
    f1_name = b"../../../../../../../../../../../../../../../../home/user/malicious.txt".ljust(256, b"\0")
    f1_content = b"you got hacked"
    f.write(f1_name)
    f.write(struct.pack("<I", len(f1_content)))
    f.write(f1_content)

    # File 2
    f2_name = b"database.wal".ljust(256, b"\0")

    rec1 = struct.pack("<III", 0x4C415752, 100, 5) + b"hello"
    rec2 = struct.pack("<III", 0x4C415752, 999, 15) + b"FLAG{w4l_p4rs3}"
    wal_content = rec1 + rec2

    f.write(f2_name)
    f.write(struct.pack("<I", len(wal_content)))
    f.write(wal_content)
'

    chmod -R 777 /home/user
