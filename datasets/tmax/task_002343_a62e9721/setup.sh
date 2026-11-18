#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev
pip3 install pytest

mkdir -p /app/bin
mkdir -p /home/user/repo/archives

# Create legacy parser C code
cat << 'EOF' > /tmp/legacy_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

char schema[256][256] = {0};

void parse_schema(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return;
    char line[512];
    while (fgets(line, sizeof(line), f)) {
        unsigned int type;
        char name[256];
        if (sscanf(line, "%02X:%255s", &type, name) == 2) {
            if (type < 256) strcpy(schema[type], name);
        }
    }
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        printf("Usage: /app/bin/legacy_parser <path_to_schema_conf> <path_to_arf_file>\n");
        return 1;
    }
    parse_schema(argv[1]);
    FILE *f = fopen(argv[2], "rb");
    if (!f) return 1;
    unsigned char magic[4];
    if (fread(magic, 1, 4, f) != 4 || memcmp(magic, "ARF1", 4) != 0) {
        printf("ERR: Bad Magic\n");
        return 1;
    }
    unsigned int uncompressed_size;
    if (fread(&uncompressed_size, 1, 4, f) != 4) {
        printf("ERR: Zlib fail\n");
        return 2;
    }

    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 8, SEEK_SET);
    long compressed_size = file_size - 8;
    if (compressed_size < 0) compressed_size = 0;

    unsigned char *comp_buf = malloc(compressed_size);
    fread(comp_buf, 1, compressed_size, f);
    fclose(f);

    unsigned char *uncomp_buf = malloc(uncompressed_size + 1);
    unsigned long destLen = uncompressed_size;
    if (uncompress(uncomp_buf, &destLen, comp_buf, compressed_size) != Z_OK || destLen != uncompressed_size) {
        printf("ERR: Zlib fail\n");
        return 2;
    }

    unsigned long offset = 0;
    while (offset < destLen) {
        if (offset + 3 > destLen) {
            printf("ERR: Truncated TLV\n");
            return 3;
        }
        unsigned char type = uncomp_buf[offset];
        unsigned short length = uncomp_buf[offset+1] | (uncomp_buf[offset+2] << 8);
        offset += 3;
        if (offset + length > destLen) {
            printf("ERR: Truncated TLV\n");
            return 3;
        }

        if (schema[type][0] != '\0') {
            printf("[%s] ", schema[type]);
        } else {
            printf("[UNKNOWN_%02X] ", type);
        }

        for (int i = 0; i < length; i++) {
            printf("%02X", uncomp_buf[offset + i]);
        }
        printf("\n");
        offset += length;
    }

    return 0;
}
EOF

gcc -O2 /tmp/legacy_parser.c -o /app/bin/legacy_parser -lz
strip /app/bin/legacy_parser
rm /tmp/legacy_parser.c

# Create Python script to generate archives
cat << 'EOF' > /tmp/gen_data.py
import zlib
import struct
import tarfile
import os

os.makedirs("/tmp/target", exist_ok=True)
with open("/tmp/target/schema.conf", "w") as f:
    f.write("01:FILE_NAME\n02:BUILD_DATE\n03:CHECKSUM\nFF:SIGNATURE\n")

def make_arf(filename, tlvs):
    uncomp = b""
    for t, v in tlvs:
        uncomp += struct.pack("<BH", t, len(v)) + v
    comp = zlib.compress(uncomp)
    with open(filename, "wb") as f:
        f.write(b"ARF1")
        f.write(struct.pack("<I", len(uncomp)))
        f.write(comp)

make_arf("/tmp/target/sample1.arf", [(1, b"hello.txt"), (2, b"2023-01-01")])
make_arf("/tmp/target/sample2.arf", [(3, b"\xaa\xbb\xcc\xdd"), (255, b"signature")])

with tarfile.open("/home/user/repo/archives/target.tar.gz", "w:gz") as tar:
    tar.add("/tmp/target", arcname=".")

for i in range(3):
    with tarfile.open(f"/home/user/repo/archives/dummy{i}.tar.gz", "w:gz") as tar:
        pass
EOF

python3 /tmp/gen_data.py
rm /tmp/gen_data.py /tmp/target/*
rmdir /tmp/target

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user

# Set sticky bit AFTER chmod 777 to ensure it persists
chmod +t /home/user/repo/archives/target.tar.gz
