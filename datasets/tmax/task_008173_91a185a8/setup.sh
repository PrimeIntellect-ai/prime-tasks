#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/src /home/user/data

    cat << 'EOF' > /home/user/src/data_processor.c
#include <stdio.h>
#include <stdint.h>

void process_data(const char* filepath) {
    FILE *f = fopen(filepath, "rb");
    if (!f) return;
    int32_t val;
    fread(&val, sizeof(int32_t), 1, f);
    fclose(f);
    printf("{\"value\": %d}\n", val);
}
EOF

    cat << 'EOF' > /home/user/src/test_runner.c
#include <stdio.h>

extern void process_data(const char* filepath);

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    process_data(argv[1]);
    return 0;
}
EOF

    python3 -c "with open('/home/user/data/input.dat', 'wb') as f: f.write(b'\x2a\x00\x00\x00')"

    chmod -R 777 /home/user
