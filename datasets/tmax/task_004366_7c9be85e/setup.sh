#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc strace rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.cache

    python3 -c '
import struct
with open("/home/user/.cache/.data.wal", "wb") as f:
    f.write(b"CORR")
    for i in range(1, 10001):
        f.write(struct.pack("<f", 1.0 + 1.0/i))
'

    cat << 'EOF' > /tmp/suspicious.c
#include <stdio.h>
int main() {
    FILE *f = fopen("/home/user/.cache/.data.wal", "r");
    if (f) fclose(f);
    return 0;
}
EOF
    gcc /tmp/suspicious.c -o /home/user/suspicious_bin
    rm /tmp/suspicious.c
    chmod +x /home/user/suspicious_bin

    cat << 'EOF' > /home/user/recover.rs
use std::fs::File;
use std::io::Read;

fn main() {
    // TODO: Update path based on system call trace
    let mut file = File::open("INSERT_PATH_HERE").unwrap();
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer).unwrap();

    // BUG 1: Failing to skip the 4-byte corrupted WAL header
    let data = &buffer[0..]; 

    // BUG 2: Precision loss and convergence failure using f32 for accumulation
    let mut result: f32 = 1.0; 

    for chunk in data.chunks_exact(4) {
        let val = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
        result *= val;
    }

    println!("{:.5}", result);
}
EOF

    chmod -R 777 /home/user
