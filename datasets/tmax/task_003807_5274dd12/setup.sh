#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc inotify-tools xxd strace ltrace
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /home/user/accepted
    mkdir -p /home/user/rejected
    mkdir -p /tests/corpora/clean
    mkdir -p /tests/corpora/evil
    mkdir -p /app

    # Create the validator source
    cat << 'EOF' > /app/validator.c
#include <stdio.h>
#include <stdint.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t magic[4];
    if (fread(magic, 1, 4, f) != 4) { fclose(f); return 1; }
    if (magic[0] != 'P' || magic[1] != 'D' || magic[2] != 'A' || magic[3] != 'T') { fclose(f); return 1; }

    uint32_t count;
    if (fread(&count, 4, 1, f) != 1) { fclose(f); return 1; }

    for (uint32_t i = 0; i < count; i++) {
        uint32_t offset, size;
        if (fread(&offset, 4, 1, f) != 1) { fclose(f); return 1; }
        if (fread(&size, 4, 1, f) != 1) { fclose(f); return 1; }

        if ((long)offset + (long)size > file_size || (long)offset + (long)size < (long)offset) { fclose(f); return 1; }

        uint16_t prev_char = 0;
        uint16_t curr_char;
        int null_found = 0;
        while (fread(&curr_char, 2, 1, f) == 1) {
            if (curr_char == 0) {
                null_found = 1;
                break;
            }
            if (curr_char == 0x002F) { fclose(f); return 1; }
            if (prev_char == 0x002E && curr_char == 0x002E) { fclose(f); return 1; }
            prev_char = curr_char;
        }
        if (!null_found) { fclose(f); return 1; }
    }

    fclose(f);
    return 0;
}
EOF

    gcc -O2 /app/validator.c -o /app/validator
    strip /app/validator
    rm /app/validator.c

    # Generate corpora and sample
    cat << 'EOF' > /tmp/gen.py
import os
import struct

def write_pdat(path, entries, magic=b"PDAT", file_size=1000):
    with open(path, "wb") as f:
        f.write(magic)
        f.write(struct.pack("<I", len(entries)))
        for offset, size, name in entries:
            f.write(struct.pack("<II", offset, size))
            f.write(name.encode("utf-16le") + b"\x00\x00")
        current_size = f.tell()
        if current_size < file_size:
            f.write(b"\x00" * (file_size - current_size))

write_pdat("/app/sample.pdat", [(100, 200, "test.txt")])

for i in range(50):
    write_pdat(f"/tests/corpora/clean/clean_{i}.pdat", [(100, 200, f"file_{i}.txt")])

for i in range(50):
    if i < 10:
        write_pdat(f"/tests/corpora/evil/evil_{i}.pdat", [(100, 200, "test.txt")], magic=b"BADT")
    elif i < 20:
        write_pdat(f"/tests/corpora/evil/evil_{i}.pdat", [(0xFFFFFFFF, 10, "test.txt")])
    elif i < 30:
        write_pdat(f"/tests/corpora/evil/evil_{i}.pdat", [(100, 200, "dir/../test.txt")])
    elif i < 40:
        write_pdat(f"/tests/corpora/evil/evil_{i}.pdat", [(100, 200, "/etc/passwd")])
    else:
        with open(f"/tests/corpora/evil/evil_{i}.pdat", "wb") as f:
            f.write(b"PDAT\x01\x00\x00\x00")
EOF

    python3 /tmp/gen.py
    rm /tmp/gen.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
