#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev sqlite3 libsqlite3-dev rustc cargo
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/chksum.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <zlib.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *buf = malloc(len);
    if (len > 0) fread(buf, 1, len, f);
    fclose(f);

    uint32_t crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, buf, len);
    crc ^= 0x87654321;
    printf("%08x\n", crc);
    free(buf);
    return 0;
}
EOF
    gcc -O2 /tmp/chksum.c -o /app/legacy_chksum -lz
    strip /app/legacy_chksum
    rm /tmp/chksum.c

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/telemetry.db "CREATE TABLE readings_v1 (id INTEGER, dev_id INTEGER, metric REAL);"
    sqlite3 /home/user/telemetry.db "INSERT INTO readings_v1 VALUES (1, 100, 42.5);"

    mkdir -p /home/user/ingester/src
    cat << 'EOF' > /home/user/ingester/Cargo.toml
[package]
name = "ingester"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = "0.29.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/ingester/src/main.rs
use std::net::TcpListener;
use std::io::Read;

fn main() {
    let listener = TcpListener::bind("127.0.0.1:9999").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let mut len_buf = [0u8; 4];
        if stream.read_exact(&mut len_buf).is_err() { continue; }
        let len = u32::from_le_bytes(len_buf) as usize;

        let mut chk_buf = [0u8; 4];
        if stream.read_exact(&mut chk_buf).is_err() { continue; }
        let _chk = u32::from_le_bytes(chk_buf);

        // intentional memory leak for the task
        let mut payload = vec![0u8; len];
        if stream.read_exact(&mut payload).is_ok() {
            let _leaked = Box::leak(payload.into_boxed_slice());
        }
    }
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
