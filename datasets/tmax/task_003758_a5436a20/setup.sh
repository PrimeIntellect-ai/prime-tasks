#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc build-essential tar coreutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/legacy_indexer.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int is_valid_utf8(const uint8_t *data, size_t len) {
    size_t i = 0;
    while (i < len) {
        if (data[i] <= 0x7F) i++;
        else if ((data[i] & 0xE0) == 0xC0) {
            if (i + 1 >= len || (data[i+1] & 0xC0) != 0x80) return 0;
            i += 2;
        } else if ((data[i] & 0xF0) == 0xE0) {
            if (i + 2 >= len || (data[i+1] & 0xC0) != 0x80 || (data[i+2] & 0xC0) != 0x80) return 0;
            i += 3;
        } else if ((data[i] & 0xF8) == 0xF0) {
            if (i + 3 >= len || (data[i+1] & 0xC0) != 0x80 || (data[i+2] & 0xC0) != 0x80 || (data[i+3] & 0xC0) != 0x80) return 0;
            i += 4;
        } else {
            return 0;
        }
    }
    return 1;
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t magic[6];
    if (fread(magic, 1, 6, f) != 6) { fclose(f); return 1; }
    uint8_t expected_magic[6] = {0xAB, 0xCD, 0xEF, 0x01, 0x02, 0x03};
    if (memcmp(magic, expected_magic, 6) != 0) { fclose(f); return 1; }

    uint32_t L;
    if (fread(&L, 1, 4, f) != 4) { fclose(f); return 1; }

    if (L != file_size - 10) {
        int *p = NULL;
        *p = 0;
    }

    uint8_t *payload = malloc(L);
    if (!payload || fread(payload, 1, L, f) != L) { free(payload); fclose(f); return 1; }

    if (!is_valid_utf8(payload, L)) {
        while (1) {}
    }

    free(payload);
    fclose(f);
    return 0;
}
EOF

gcc -s -O2 /tmp/legacy_indexer.c -o /app/legacy_indexer

mkdir -p /home/user/raw_data
mkdir -p /home/user/validation

cat << 'EOF' > /tmp/generate.py
import os
import struct

def make_file(path, magic, L, payload):
    with open(path, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<I', L))
        f.write(payload)

def generate_dataset(base_dir, num_clean, num_evil):
    os.makedirs(os.path.join(base_dir, 'clean'), exist_ok=True)
    os.makedirs(os.path.join(base_dir, 'evil'), exist_ok=True)

    valid_magic = b'\xAB\xCD\xEF\x01\x02\x03'

    for i in range(num_clean):
        payload = f"Valid UTF-8 payload {i} padding to make it larger... ".encode('utf-8') * 500
        make_file(f"{base_dir}/clean/{i}.bin", valid_magic, len(payload), payload)

    for i in range(num_evil):
        t = i % 3
        if t == 0:
            payload = b"test" * 500
            make_file(f"{base_dir}/evil/{i}.bin", b'\x00'*6, len(payload), payload)
        elif t == 1:
            payload = b"test" * 500
            make_file(f"{base_dir}/evil/{i}.bin", valid_magic, len(payload) + 1, payload)
        elif t == 2:
            payload = b"Invalid \xFF UTF-8 padding... " * 500
            make_file(f"{base_dir}/evil/{i}.bin", valid_magic, len(payload), payload)

generate_dataset('/tmp/corpora', 5, 5)
generate_dataset('/home/user/validation', 20, 20)
EOF

python3 /tmp/generate.py

cd /tmp
tar -czf corpora.tar.gz corpora
# Ensure split produces parta and partb by making the split size half the archive size
ARCHIVE_SIZE=$(stat -c%s corpora.tar.gz)
SPLIT_SIZE=$((ARCHIVE_SIZE / 2 + 100))
split -b ${SPLIT_SIZE} corpora.tar.gz /home/user/raw_data/corpora.tar.gz.part

# Just in case split names them differently or doesn't produce partb
if [ ! -f /home/user/raw_data/corpora.tar.gz.partb ]; then
    split -b 1K corpora.tar.gz /home/user/raw_data/corpora.tar.gz.part
fi
# Rename aa to a, ab to b if needed
if [ -f /home/user/raw_data/corpora.tar.gz.partaa ]; then
    mv /home/user/raw_data/corpora.tar.gz.partaa /home/user/raw_data/corpora.tar.gz.parta
    mv /home/user/raw_data/corpora.tar.gz.partab /home/user/raw_data/corpora.tar.gz.partb
fi

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
