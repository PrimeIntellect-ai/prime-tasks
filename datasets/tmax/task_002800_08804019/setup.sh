#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc make
pip3 install pytest

mkdir -p /app/libtokenparse-1.0 /app/corpus/clean /app/corpus/evil

cat << 'EOF' > /app/libtokenparse-1.0/tokenparse.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>

int parse_token(const uint8_t *payload, size_t size) {
    if (size < 2) return -1;
    uint16_t length;
    memcpy(&length, payload, 2);
    char buffer[256];
    // VULNERABILITY: Missing check if length > 256
    memcpy(buffer, payload + 2, length);
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) return -1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return -1;
    uint8_t data[1024];
    size_t n = fread(data, 1, sizeof(data), f);
    fclose(f);
    if (parse_token(data, n) != 0) {
        return 1;
    }
    return 0;
}
EOF

cat << 'EOF' > /app/libtokenparse-1.0/Makefile
verify_token: tokenparse.c
    gcc -o verify_token tokenparse.c
EOF

python3 -c "with open('/app/corpus/clean/tok1.bin', 'wb') as f: f.write(b'\x04\x00TEST')"
python3 -c "with open('/app/corpus/evil/tok1.bin', 'wb') as f: f.write(b'\x2C\x01' + b'A'*300)"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
