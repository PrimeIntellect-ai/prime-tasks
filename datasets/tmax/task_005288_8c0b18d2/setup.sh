#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Create the vulnerable C program (extractor)
    cat << 'EOF' > /tmp/ext.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    char magic[6];
    if (fread(magic, 1, 6, f) != 6 || memcmp(magic, "FARCHV", 6) != 0) return 1;

    int c1, c2;
    while ((c1 = fgetc(f)) != EOF) {
        c2 = fgetc(f);
        if (c1 == 0 && c2 == 0) break;
    }

    while (1) {
        unsigned int N;
        if (fread(&N, 4, 1, f) != 1) break;
        char filename[1024]; // buffer overflow vulnerability
        fread(filename, 1, N, f);
        filename[N] = '\0';

        unsigned long long S;
        fread(&S, 8, 1, f);

        // path traversal vulnerability: fopen(filename, "wb")
        // we just skip the data for the fixture
        fseek(f, S, SEEK_CUR);
    }
    fclose(f);
    return 0;
}
EOF

    gcc -O2 /tmp/ext.c -o /app/fast-extractor
    strip /app/fast-extractor
    chmod +x /app/fast-extractor
    rm /tmp/ext.c

    # Generate the corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import os
import struct

def make_archive(path, config, files):
    with open(path, 'wb') as f:
        f.write(b'FARCHV')
        f.write(config)
        f.write(b'\x00\x00')
        for name, data in files:
            name_b = name.encode('utf-8')
            f.write(struct.pack('<I', len(name_b)))
            f.write(name_b)
            f.write(struct.pack('<Q', len(data)))
            f.write(data)

make_archive('/app/corpus/clean/1.arc', '{"a":1}'.encode('utf-16le'), [('test.txt', b'hello')])
make_archive('/app/corpus/clean/2.arc', '{"b":2}'.encode('utf-16le'), [('dir/test.txt', b'world')])

make_archive('/app/corpus/evil/1.arc', '{"a":1}'.encode('utf-16le'), [('../test.txt', b'hello')])
make_archive('/app/corpus/evil/2.arc', '{"a":1}'.encode('utf-16le'), [('/etc/passwd', b'hello')])
make_archive('/app/corpus/evil/3.arc', '{"a":1}'.encode('utf-16le'), [('..\\test.txt', b'hello')])

# invalid utf16
with open('/app/corpus/evil/4.arc', 'wb') as f:
    f.write(b'FARCHV')
    f.write(b'\x01\x02\x03') # odd bytes
    f.write(b'\x00\x00')
    f.write(struct.pack('<I', 1) + b'a' + struct.pack('<Q', 1) + b'b')

# large N
with open('/app/corpus/evil/5.arc', 'wb') as f:
    f.write(b'FARCHV')
    f.write('{"a":1}'.encode('utf-16le'))
    f.write(b'\x00\x00')
    f.write(struct.pack('<I', 0xFFFFFFFF))
    f.write(b'a')
EOF

    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
