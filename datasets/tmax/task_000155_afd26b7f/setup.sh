#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil /home/user/samples

    # Create C source for pka_extract
    cat << 'EOF' > /app/pka_extract.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/stat.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if(argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if(!f) return 1;
    char magic[4];
    if (fread(magic, 1, 4, f) != 4) return 1;
    if(memcmp(magic, "PKA\x01", 4) != 0) return 1;
    uint32_t count;
    if (fread(&count, 4, 1, f) != 1) return 1;
    for(uint32_t i=0; i<count; i++) {
        uint16_t plen;
        if (fread(&plen, 2, 1, f) != 1) return 1;
        char *path = malloc(plen + 1);
        if (fread(path, 1, plen, f) != plen) return 1;
        path[plen] = 0;
        uint8_t type;
        if (fread(&type, 1, 1, f) != 1) return 1;
        uint32_t dsize;
        if (fread(&dsize, 4, 1, f) != 1) return 1;
        char *data = malloc(dsize + 1);
        if (fread(data, 1, dsize, f) != dsize) return 1;
        data[dsize] = 0;

        if(type == 0) {
            FILE *out = fopen(path, "wb");
            if(out) { fwrite(data, 1, dsize, out); fclose(out); }
        } else if(type == 1) {
            mkdir(path, 0777);
        } else if(type == 2) {
            symlink(data, path);
        }
        free(path);
        free(data);
    }
    fclose(f);
    return 0;
}
EOF

    gcc -O2 /app/pka_extract.c -o /app/pka_extract
    strip /app/pka_extract
    rm /app/pka_extract.c

    # Python script to generate the .pka files
    cat << 'EOF' > /tmp/gen_pka.py
import struct
import os

def write_pka(path, entries):
    with open(path, 'wb') as f:
        f.write(b'PKA\x01')
        f.write(struct.pack('<I', len(entries)))
        for e in entries:
            epath, etype, edata = e
            epath_b = epath.encode('utf-8')
            f.write(struct.pack('<H', len(epath_b)))
            f.write(epath_b)
            f.write(struct.pack('<B', etype))
            if etype == 1:
                f.write(struct.pack('<I', 0))
            elif etype == 2:
                edata_b = edata.encode('utf-8')
                f.write(struct.pack('<I', len(edata_b)))
                f.write(edata_b)
            else:
                f.write(struct.pack('<I', len(edata)))
                f.write(edata)

# Generate samples
write_pka('/home/user/samples/safe.pka', [('file.txt', 0, b'hello'), ('dir', 1, b''), ('link', 2, 'file.txt')])
write_pka('/home/user/samples/malicious.pka', [('../bad.txt', 0, b'bad')])

# Generate clean
for i in range(25):
    write_pka(f'/app/corpora/clean/clean_{i}.pka', [(f'dir{i}/file.txt', 0, b'data'), (f'dir{i}/link', 2, 'file.txt')])

# Generate evil
for i in range(25):
    if i % 4 == 0:
        write_pka(f'/app/corpora/evil/evil_{i}.pka', [(f'/etc/shadow', 0, b'bad')])
    elif i % 4 == 1:
        write_pka(f'/app/corpora/evil/evil_{i}.pka', [(f'a/../../tmp/bad', 0, b'bad')])
    elif i % 4 == 2:
        write_pka(f'/app/corpora/evil/evil_{i}.pka', [(f'link', 2, '/etc/passwd')])
    else:
        write_pka(f'/app/corpora/evil/evil_{i}.pka', [(f'link', 2, '../../etc/passwd')])
EOF

    python3 /tmp/gen_pka.py
    rm /tmp/gen_pka.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
