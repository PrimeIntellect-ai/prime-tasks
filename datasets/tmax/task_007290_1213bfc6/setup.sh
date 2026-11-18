#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    # Create input text
    echo -n "secret debugging phrase" > input.txt

    # Create the C source code, compile it, and remove it
    cat << 'EOF' > processor.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#pragma pack(push, 1)
struct Record {
    uint32_t magic;
    uint16_t len;
};
#pragma pack(pop)

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <input.bin> <output.txt>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        perror("fopen");
        return 1;
    }

    struct Record rec;
    if (fread(&rec, sizeof(rec), 1, f) != 1) {
        fprintf(stderr, "Failed to read header. Expected %zu bytes.\n", sizeof(rec));
        fclose(f);
        return 1;
    }

    if (rec.magic != 0xCAFEBABE) {
        fprintf(stderr, "Invalid magic number: %x\n", rec.magic);
        fclose(f);
        return 2;
    }

    if (rec.len == 0 || rec.len > 10000) {
        fprintf(stderr, "Invalid length: %u\n", rec.len);
        fclose(f);
        return 3;
    }

    char *buf = malloc(rec.len + 1);
    if (!buf) return 4;

    if (fread(buf, 1, rec.len, f) != rec.len) {
        fprintf(stderr, "Failed to read string data.\n");
        free(buf);
        fclose(f);
        return 5;
    }
    buf[rec.len] = '\0';
    fclose(f);

    // Process string (convert to uppercase)
    for(int i = 0; i < rec.len; i++) {
        if(buf[i] >= 'a' && buf[i] <= 'z') {
            buf[i] -= 32;
        }
    }

    FILE *out = fopen(argv[2], "w");
    if (!out) {
        free(buf);
        return 1;
    }
    fprintf(out, "PROCESSED: %s\n", buf);
    fclose(out);
    free(buf);

    return 0;
}
EOF

    gcc -O2 processor.c -o processor
    rm processor.c

    # Create the broken Python script
    cat << 'EOF' > pipeline.py
import struct
import sys
import os

def main():
    input_file = '/home/user/pipeline/input.txt'
    output_bin = '/home/user/pipeline/data.bin'

    if not os.path.exists(input_file):
        print(f"Error: {input_file} not found")
        sys.exit(1)

    with open(input_file, 'r', encoding='utf-8') as f:
        text = f.read().strip()

    # WRONG MAGIC NUMBER
    magic = 0xDEADBEEF 

    # WRONG ENCODING (utf-16 instead of utf-8/ascii)
    text_bytes = text.encode('utf-16')

    with open(output_bin, 'wb') as f:
        # WRONG STRUCT FORMAT ('<I i' uses a 4-byte int for length instead of 2-byte short)
        f.write(struct.pack('<I i', magic, len(text_bytes)))
        f.write(text_bytes)

if __name__ == '__main__':
    main()
EOF

    chmod +x processor

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
