#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev rustc cargo
    pip3 install pytest

    mkdir -p /home/user/src /home/user/artifacts /home/user/bin

    cat << 'EOF' > /home/user/src/parser.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    int len = 0;
    fread(&len, sizeof(int), 1, f);

    // BUG: Missing space for null terminator
    char *buf = malloc(len);
    fread(buf, 1, len, f);

    // BUG: No null terminator added, leads to UB when printing
    printf("METADATA: %s\n", buf);

    free(buf);
    // BUG: Double free
    free(buf);

    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/verifier.rs
use std::env;

fn compute_checksum(s: String) -> u16 {
    let mut sum: u16 = 0;
    for b in s.bytes() {
        sum = sum.wrapping_add(b as u16);
    }
    sum
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        std::process::exit(1);
    }
    let metadata = args[1].clone();

    // BUG: `metadata` is moved here
    let chk = compute_checksum(metadata);

    // BUG: `metadata` is used after move
    println!("CHECKSUM: {:04X} for length {}", chk, metadata.len());
}
EOF

    cat << 'EOF' > /tmp/gen_bin.py
import struct
metadata = b"Build_v1.0.42_Release"
with open("/home/user/artifacts/app_v1.bin", "wb") as f:
    f.write(struct.pack("<I", len(metadata)))
    f.write(metadata)
EOF
    python3 /tmp/gen_bin.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
