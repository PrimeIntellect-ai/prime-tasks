#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip e2fsprogs e2tools sleuthkit gcc
    pip3 install pytest

    mkdir -p /app

    # Generate telemetry.db
    cat << 'EOF' > /tmp/gen_db.py
import sqlite3
import base64

def encode(text):
    xored = bytes([b ^ 0x5A for b in text.encode()])
    return base64.b64encode(xored).decode()

conn = sqlite3.connect('/tmp/telemetry.db')
c = conn.cursor()
c.execute('CREATE TABLE telemetry (id INTEGER, timestamp INTEGER, encoded_payload TEXT)')
data = [
    (1, 1600000000, encode('{"status": "ok", "value": 42}')),
    (2, 1600000010, encode('{"status": "error", "value": 0}')),
    (3, 1600000020, encode('{"status": "ok", "value": 100}')),
    (4, 1600000030, encode('{"status": "ok", "value": 200}')),
    (5, 1600000040, encode('{"status": "warning", "value": 50}'))
]
c.executemany('INSERT INTO telemetry VALUES (?, ?, ?)', data)
conn.commit()
conn.close()
EOF
    python3 /tmp/gen_db.py

    # Create ext4 image and copy/delete DB
    dd if=/dev/zero of=/app/telemetry_data.img bs=1M count=10
    mkfs.ext4 -F /app/telemetry_data.img
    e2cp /tmp/telemetry.db /app/telemetry_data.img:/
    e2rm /app/telemetry_data.img:/telemetry.db

    # Create decoder binary
    cat << 'EOF' > /tmp/decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char input[1024];
    if (!fgets(input, sizeof(input), stdin)) return 1;
    input[strcspn(input, "\r\n")] = 0;
    if (strlen(input) > 100) {
        volatile int *p = NULL;
        *p = 1;
    }
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "python3 -c \"import sys, base64; print(bytes([b ^ 0x5A for b in base64.b64decode(sys.argv[1])]).decode())\" '%s'", input);
    system(cmd);
    return 0;
}
EOF
    gcc -s -o /app/decoder.bin /tmp/decoder.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
