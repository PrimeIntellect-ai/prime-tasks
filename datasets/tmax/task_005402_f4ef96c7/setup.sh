#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create the bin_to_json utility
    mkdir -p /app
    cat << 'EOF' > /tmp/bin_to_json.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    uint32_t ts;
    uint8_t level;
    uint16_t msg_len;
    const char *levels[] = {"DEBUG", "INFO", "WARN", "ERROR"};

    while (fread(&ts, 4, 1, f) == 1) {
        if (fread(&level, 1, 1, f) != 1) break;
        if (fread(&msg_len, 2, 1, f) != 1) break;
        char *msg = malloc(msg_len + 1);
        if (fread(msg, 1, msg_len, f) != msg_len) { free(msg); break; }
        msg[msg_len] = '\0';

        const char *lvl_str = (level <= 3) ? levels[level] : "UNKNOWN";
        printf("{\"timestamp\": %u, \"level\": \"%s\", \"message\": \"%s\"}\n", ts, lvl_str, msg);
        free(msg);
    }
    fclose(f);
    return 0;
}
EOF
    gcc -O2 -s /tmp/bin_to_json.c -o /app/bin_to_json
    rm /tmp/bin_to_json.c

    # Generate the raw_logs.tar file
    cat << 'EOF' > /tmp/gen_logs.py
import struct
import random
import tarfile
import os

levels = [0, 1, 2, 3]
weights = [0.7, 0.1, 0.1, 0.1]
messages = ["System nominal", "Disk usage high", "Connection timeout", "User logged in", "Cache miss", "Data flushed"]

os.chdir('/tmp')
with tarfile.open("/home/user/raw_logs.tar", "w") as tar:
    for i in range(5):
        filename = f"log_{i}.binlog"
        with open(filename, "wb") as f:
            for _ in range(50000):
                ts = 1610000000 + random.randint(0, 10000)
                lvl = random.choices(levels, weights)[0]
                msg = random.choice(messages).encode('ascii')
                # Format: 4-byte ts, 1-byte level, 2-byte msg len
                f.write(struct.pack("<IBH", ts, lvl, len(msg)))
                f.write(msg)
        tar.add(filename)
        os.remove(filename)
EOF
    python3 /tmp/gen_logs.py
    rm /tmp/gen_logs.py

    # Set permissions
    chmod -R 777 /home/user
