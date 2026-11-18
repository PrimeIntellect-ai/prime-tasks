#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make binutils file libc6-dev
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/validator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;

    char magic[4];
    if (fread(magic, 1, 4, f) != 4) return 1;
    if (memcmp(magic, "ARCH", 4) != 0) return 1;

    uint32_t proj_id;
    if (fread(&proj_id, 4, 1, f) != 1) return 1;

    uint16_t num_files;
    if (fread(&num_files, 2, 1, f) != 1) return 1;

    for (int i = 0; i < num_files; i++) {
        uint16_t name_len;
        if (fread(&name_len, 2, 1, f) != 1) return 1;

        char* name = malloc(name_len);
        if (fread(name, 1, name_len, f) != name_len) return 1;
        free(name);

        uint32_t content_len;
        if (fread(&content_len, 4, 1, f) != 1) return 1;

        fseek(f, content_len, SEEK_CUR);
    }

    // Ensure we are at EOF
    int c = fgetc(f);
    if (c != EOF) return 1;

    fclose(f);
    return 0;
}
EOF

gcc -O2 /tmp/validator.c -o /app/validator
strip /app/validator
chmod +x /app/validator
rm /tmp/validator.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
