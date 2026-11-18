#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install --default-timeout=100 pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/validator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    unsigned char magic[4];
    if (fread(magic, 1, 4, f) != 4) { fclose(f); return 1; }
    if (memcmp(magic, "BKP\0", 4) != 0) { fclose(f); return 1; }

    uint32_t L_be;
    if (fread(&L_be, 1, 4, f) != 4) { fclose(f); return 1; }
    uint32_t L = ntohl(L_be);

    if (L > 100000000) { fclose(f); return 1; }
    unsigned char *meta = malloc(L + 1);
    if (!meta) { fclose(f); return 1; }
    if (fread(meta, 1, L, f) != L) { free(meta); fclose(f); return 1; }
    meta[L] = '\0';

    if (strstr((char*)meta, "MALWARE") != NULL) { free(meta); fclose(f); return 1; }

    for (uint32_t i = 0; i < L; i++) {
        if (meta[i] < 0x20 || meta[i] > 0x7E) { free(meta); fclose(f); return 1; }
    }

    free(meta);
    fclose(f);
    return 0;
}
EOF
    gcc -O2 -s /tmp/validator.c -o /app/legacy_validator
    rm /tmp/validator.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/corpus/clean /home/user/corpus/evil /home/user/incoming

    python3 -c "
import os, struct, time
def make_file(path, magic, L, meta, mtime_days_ago=0):
    with open(path, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('>I', L))
        f.write(meta)
        f.write(b'extra data')
    if mtime_days_ago > 0:
        t = time.time() - (mtime_days_ago * 86400)
        os.utime(path, (t, t))

make_file('/home/user/corpus/clean/c1.bkp', b'BKP\x00', 5, b'hello')
make_file('/home/user/corpus/clean/c2.bkp', b'BKP\x00', 10, b'world12345')

make_file('/home/user/corpus/evil/e1.bkp', b'BKP\x01', 5, b'hello')
make_file('/home/user/corpus/evil/e2.bkp', b'BKP\x00', 7, b'MALWARE')
make_file('/home/user/corpus/evil/e3.bkp', b'BKP\x00', 5, b'he\x01lo')

make_file('/home/user/incoming/i1.bkp', b'BKP\x00', 4, b'good', 2)
make_file('/home/user/incoming/i2.bkp', b'BKP\x00', 4, b'good', 10)
make_file('/home/user/incoming/i3.bkp', b'BKP\x00', 7, b'MALWARE', 2)
"

    chmod -R 777 /home/user
