#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 git gcc gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Setup Data Directory and Corrupted SQLite DB
    mkdir -p /home/user/data
    cd /home/user/data

    python3 -c '
import sqlite3
import os

key = "SECRET_KEY_445"
text = "SYSTEM_RECOVERY_SUCCESS_9912"
res = []
for i in range(len(text)):
    res.append(f"{ord(text[i]) ^ ord(key[i % len(key)]):02x}")
payload = "".join(res)

conn = sqlite3.connect("metrics.db")
conn.execute("PRAGMA journal_mode=WAL")
conn.execute("CREATE TABLE events (id INTEGER PRIMARY KEY, event_type TEXT, payload TEXT)")
conn.execute(f"INSERT INTO events (event_type, payload) VALUES (\"critical_crash\", \"{payload}\")")
conn.commit()

# Exit immediately to avoid SQLite cleanup, leaving the WAL file intact
os._exit(0)
'

    # Corrupt the main DB but leave WAL
    dd if=/dev/urandom of=metrics.db bs=1024 count=1 conv=notrunc

    # 2. Setup Git Repository and C Code
    mkdir -p /home/user/profiler_app
    cd /home/user/profiler_app
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <arpa/inet.h>

int main(int argc, char** argv) {
    if (argc < 3) {
        printf("Usage: %s <hex_payload> <key>\n", argv[0]);
        return 1;
    }

    const char* hex = argv[1];
    const char* key = argv[2];
    size_t hex_len = strlen(hex);
    size_t data_len = hex_len / 2;

    uint8_t* data = malloc(data_len);
    for (size_t i = 0; i < data_len; i++) {
        sscanf(hex + 2*i, "%2hhx", &data[i]);
    }

    // Simulate reading length prefix from a little-endian source
    // BUG: ntohl assumes network byte order (big-endian). If we give it little-endian,
    // on a little-endian machine it swaps it to big-endian, causing a massive length!
    uint32_t prefix_len = data_len;
    uint32_t processed_len = ntohl(prefix_len); // This is the bug causing "performance/hang" issues

    if (processed_len > 100000) {
        // Infinite loop simulation due to bad length
        while(1) {}
    }

    char* out = malloc(data_len + 1);
    for (size_t i = 0; i < data_len; i++) {
        out[i] = data[i] ^ key[i % strlen(key)];
    }
    out[data_len] = '\0';

    printf("%s\n", out);
    return 0;
}
EOF
    git add decoder.c
    git commit -m "Initial commit of decoder"

    # Add hardcoded key commit
    cat << 'EOF' > decoder.c
// HARDCODED_KEY="SECRET_KEY_445"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <arpa/inet.h>

int main(int argc, char** argv) {
    if (argc < 3) {
        printf("Usage: %s <hex_payload> <key>\n", argv[0]);
        return 1;
    }

    const char* hex = argv[1];
    const char* key = argv[2];
    size_t hex_len = strlen(hex);
    size_t data_len = hex_len / 2;

    uint8_t* data = malloc(data_len);
    for (size_t i = 0; i < data_len; i++) {
        sscanf(hex + 2*i, "%2hhx", &data[i]);
    }

    uint32_t prefix_len = data_len;
    uint32_t processed_len = ntohl(prefix_len);

    if (processed_len > 100000) {
        while(1) {}
    }

    char* out = malloc(data_len + 1);
    for (size_t i = 0; i < data_len; i++) {
        out[i] = data[i] ^ key[i % strlen(key)];
    }
    out[data_len] = '\0';

    printf("%s\n", out);
    return 0;
}
EOF
    git add decoder.c
    git commit -m "Debugging with key"

    # Remove key
    sed -i '1d' decoder.c
    git add decoder.c
    git commit -m "Remove hardcoded secret key"

    chown -R user:user /home/user/data /home/user/profiler_app
    chmod -R 777 /home/user
