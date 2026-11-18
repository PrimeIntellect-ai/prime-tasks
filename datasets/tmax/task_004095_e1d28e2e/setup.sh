#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ zlib1g-dev binutils
    pip3 install pytest

    mkdir -p /home/user/configs
    mkdir -p /home/user/processed
    mkdir -p /app

    # Create json_compressor.c
    cat << 'EOF' > /app/json_compressor.c
#include <stdio.h>
#include <stdlib.h>
#include <zlib.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    FILE *in = fopen(argv[1], "rb");
    if (!in) return 1;
    fseek(in, 0, SEEK_END);
    long size = ftell(in);
    fseek(in, 0, SEEK_SET);
    unsigned char *buf = malloc(size);
    if (!buf) return 1;
    fread(buf, 1, size, in);
    fclose(in);

    unsigned long comp_size = compressBound(size);
    unsigned char *comp_buf = malloc(comp_size);
    if (!comp_buf) return 1;
    compress(comp_buf, &comp_size, buf, size);

    FILE *out = fopen(argv[2], "wb");
    if (!out) return 1;
    fwrite(comp_buf, 1, comp_size, out);
    fclose(out);

    free(buf);
    free(comp_buf);
    return 0;
}
EOF

    gcc -O2 /app/json_compressor.c -o /app/json_compressor -lz
    strip /app/json_compressor
    chmod +x /app/json_compressor

    # Generate 200 .conf files
    python3 -c "
import os, random, string
keys = ['db_host', 'db_port', 'api_key', 'timeout', 'retry_count', 'log_level', 'cache_size', 'feature_flag']
for i in range(200):
    with open(f'/home/user/configs/config_{i}.conf', 'w') as f:
        random.shuffle(keys)
        for k in keys:
            val = ''.join(random.choices(string.ascii_letters, k=10))
            f.write(f'# This is a random comment {random.randint(1,100)}\n')
            f.write(f'{k} = {val} # inline comment\n\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
