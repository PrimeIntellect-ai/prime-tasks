#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace

    python3 -c "
import struct
with open('/home/user/workspace/data.bin', 'wb') as f:
    f.write(struct.pack('<ci', b'A', 24))
    f.write(struct.pack('<ci', b'B', 36))
    f.write(struct.pack('<ci', b'A', 12))
    f.write(struct.pack('<ci', b'B', 18))
"

    printf "processor: processor.c\n    gcc -Wall -O2 processor.c -o processor\n" > /home/user/workspace/Makefile

    cat << 'EOF' > /home/user/workspace/processor.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

struct Record {
    char type;
    int32_t val;
};

int gcd(int a, int b) {
    // Missing inline assembly implementation
    return 1;
}

int main(int argc, char** argv) {
    if(argc != 2) {
        printf("Usage: %s <binary_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if(!f) {
        printf("Error opening file.\n");
        return 1;
    }

    struct Record r;
    int sumA = 0, sumB = 0;

    while(fread(&r, sizeof(struct Record), 1, f) == 1) {
        if(r.type == 'A') sumA += r.val;
        if(r.type == 'B') sumB += r.val;
    }
    fclose(f);

    int g = gcd(sumA, sumB);

    FILE *out = fopen("/home/user/workspace/result.txt", "w");
    if(out) {
        fprintf(out, "GCD: %d\n", g);
        fclose(out);
    }

    return 0;
}
EOF

    chown -R user:user /home/user/workspace
    chmod -R 777 /home/user
