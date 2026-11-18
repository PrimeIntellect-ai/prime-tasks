#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make gdb
pip3 install pytest

mkdir -p /app/parseman-1.0
cat << 'EOF' > /app/parseman-1.0/main.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    char magic[4];
    if (fread(magic, 1, 4, f) != 4 || strncmp(magic, "L0GZ", 4) != 0) {
        fclose(f);
        return 1;
    }

    while (!feof(f)) {
        uint8_t type;
        if (fread(&type, 1, 1, f) != 1) break;
        uint16_t len;
        if (fread(&len, 1, 2, f) != 2) break;

        if (type == 0x05) {
            char buf[64];
            fread(buf, 1, len, f); // BUG: Buffer overflow if len > 64
        } else {
            fseek(f, len, SEEK_CUR);
        }
    }
    fclose(f);
    return 0;
}
EOF

cat << 'EOF' > /app/parseman-1.0/Makefile
all: parseman

parseman: main.c
        gcc -g -O0 -fno-stack-protector -o parseman main.c
EOF

# Ensure spaces are used instead of tabs
sed -i 's/^\t/        /' /app/parseman-1.0/Makefile

# Create the corpora
mkdir -p /app/corpus/clean /app/corpus/evil

# Clean log 1: Valid type 0x05 with length 64
echo -ne "L0GZ\x05\x40\x00" > /app/corpus/clean/clean1.bin
head -c 64 /dev/zero >> /app/corpus/clean/clean1.bin

# Clean log 2: Valid type 0x01 with length 100
echo -ne "L0GZ\x01\x64\x00" > /app/corpus/clean/clean2.bin
head -c 100 /dev/zero >> /app/corpus/clean/clean2.bin

# Evil log 1: Type 0x05 with length 65 (Overflow!)
echo -ne "L0GZ\x05\x41\x00" > /app/corpus/evil/evil1.bin
head -c 65 /dev/zero >> /app/corpus/evil/evil1.bin

# Evil log 2: Type 0x05 with length 200 (Overflow!)
echo -ne "L0GZ\x05\xC8\x00" > /app/corpus/evil/evil2.bin
head -c 200 /dev/zero >> /app/corpus/evil/evil2.bin

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
