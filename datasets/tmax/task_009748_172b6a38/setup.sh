#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sensor_project
    cd /home/user/sensor_project

    git config --global user.email "test@example.com"
    git config --global user.name "Test User"
    git init

    cat << 'EOF' > process.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

// DECRYPT_KEY
#define SECRET_KEY 0x8BADF00D

int main() {
    FILE *f = fopen("data.bin", "rb");
    if (!f) return 1;
    uint32_t len;
    double sum = 0;
    int count = 0;
    while (fread(&len, 4, 1, f) == 1) {
        uint8_t buf[64];
        fread(buf, 1, len, f); // VULNERABILITY: buffer overflow
        for(uint32_t i=0; i<len; i++) {
            buf[i] ^= (SECRET_KEY >> ((i%4)*8)) & 0xFF;
        }
        if (len == 8) {
            double *val = (double*)buf;
            sum += *val;
            count++;
        }
    }
    if (count > 0)
        printf("Anomaly Mean: %.2f\n", sum / count);
    fclose(f);
    return 0;
}
EOF

    git add process.c
    git commit -m "Initial commit with working parser"

    sed -i 's/#define SECRET_KEY 0x8BADF00D/#define SECRET_KEY 0x00000000/' process.c
    git add process.c
    git commit -m "Oops, removing hardcoded secret key"

    python3 -c "
import struct

key = 0x8BADF00D
def encrypt(data):
    res = bytearray(data)
    for i in range(len(res)):
        res[i] ^= (key >> ((i%4)*8)) & 0xFF
    return res

with open('data.bin', 'wb') as f:
    # Valid record 1: 10.5
    f.write(struct.pack('<I', 8))
    f.write(encrypt(struct.pack('<d', 10.5)))

    # Corrupted record: length 100 (exceeds 64 buffer)
    f.write(struct.pack('<I', 100))
    f.write(encrypt(b'A'*100))

    # Valid record 2: 45.25
    f.write(struct.pack('<I', 8))
    f.write(encrypt(struct.pack('<d', 45.25)))

    # Corrupted record: length 80
    f.write(struct.pack('<I', 80))
    f.write(encrypt(b'B'*80))

    # Valid record 3: -5.75
    f.write(struct.pack('<I', 8))
    f.write(encrypt(struct.pack('<d', -5.75)))
"

    chmod -R 777 /home/user
