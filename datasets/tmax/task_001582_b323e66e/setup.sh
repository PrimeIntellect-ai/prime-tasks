#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo curl
    pip3 install pytest

    # Create the chunk_decoder
    mkdir -p /app
    cat << 'EOF' > /app/chunk_decoder.c
#include <stdio.h>
#include <stdlib.h>
int main() {
    int a = fgetc(stdin);
    if (a == EOF) return 0;
    int b = fgetc(stdin);
    if (a == 0xDE && b == 0xAD) abort();
    while (fgetc(stdin) != EOF) {}
    return 0;
}
EOF
    gcc -O2 -s /app/chunk_decoder.c -o /app/chunk_decoder
    rm /app/chunk_decoder.c

    # Generate corpora
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/corpora/evil

    cat << 'EOF' > /tmp/gen_corpora.py
import os
import struct

def write_cpack(path, entries):
    with open(path, 'wb') as f:
        for magic, filename, payload_len, payload in entries:
            f.write(magic)
            f.write(struct.pack('<H', len(filename)))
            f.write(filename.encode('cp1252'))
            f.write(struct.pack('<I', payload_len))
            f.write(payload)

write_cpack('/home/user/corpora/clean/1.cpack', [
    (b'CPCK', 'config.A', 4, b'abcd')
])
write_cpack('/home/user/corpora/clean/2.cpack', [
    (b'CPCK', 'config.A', 4, b'abcd'),
    (b'CPCK', 'config.B', 4, b'efgh')
])

write_cpack('/home/user/corpora/evil/1.cpack', [
    (b'CPCK', '../etc/passwd', 4, b'abcd')
])
write_cpack('/home/user/corpora/evil/2.cpack', [
    (b'CPCK', 'test', 4, b'\xde\xad\x00\x00')
])
write_cpack('/home/user/corpora/evil/3.cpack', [
    (b'CPCK', 'test', 0x00AA0000, b'abcd')
])
write_cpack('/home/user/corpora/evil/4.cpack', [
    (b'CPCK', '/etc/shadow', 4, b'abcd')
])
write_cpack('/home/user/corpora/evil/5.cpack', [
    (b'BADC', 'test', 4, b'abcd')
])
EOF
    python3 /tmp/gen_corpora.py
    rm /tmp/gen_corpora.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
