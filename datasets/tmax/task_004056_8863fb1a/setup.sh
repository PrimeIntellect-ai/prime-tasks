#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc upx-ucl zip unzip curl wget strace gdb binutils
    pip3 install pytest

    # Create the wal_parser binary
    mkdir -p /app/bin
    cat << 'EOF' > /tmp/wal_parser.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    unsigned char magic[] = {0xDE, 0xAD, 0xBE, 0xEF};
    int magic_pos = 0;
    int ch;
    while ((ch = getchar()) != EOF) {
        if (ch == magic[magic_pos]) {
            magic_pos++;
            if (magic_pos == 4) break;
        } else {
            magic_pos = (ch == magic[0]) ? 1 : 0;
        }
    }
    if (magic_pos != 4) return 1;

    unsigned int len;
    if (fread(&len, 1, 4, stdin) != 4) return 1;

    for (unsigned int i = 0; i < len; i++) {
        ch = getchar();
        if (ch == EOF) break;
        putchar(ch ^ 0x5A);
    }
    return 0;
}
EOF
    gcc -O2 /tmp/wal_parser.c -o /app/bin/wal_parser
    strip /app/bin/wal_parser
    upx /app/bin/wal_parser || true

    # Create the payload and split archive
    cd /tmp
    cat << 'EOF' > /tmp/make_wal.py
import struct

payload = b"This is the secret markdown documentation.\n# Header\n"
xor_payload = bytes([b ^ 0x5A for b in payload])

with open("syslog.wal", "wb") as f:
    f.write(b"random garbage before magic")
    f.write(b"\xde\xad\xbe\xef")
    f.write(struct.pack("<I", len(xor_payload)))
    f.write(xor_payload)
    f.write(b"random garbage after")
EOF
    python3 /tmp/make_wal.py

    zip archive.zip syslog.wal
    split -n 3 archive.zip part_
    mv part_aa part1.zip
    mv part_ab part2.zip
    mv part_ac part3.zip.corrupt
    echo -n "BADEOF" >> part3.zip.corrupt

    mkdir -p /home/user
    tar -czf /home/user/docs_backup.tar.gz part1.zip part2.zip part3.zip.corrupt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
