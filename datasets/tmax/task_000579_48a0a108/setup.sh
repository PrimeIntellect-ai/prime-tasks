#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust /opt/cargo

    mkdir -p /home/user/hailstone_ffi/c_src
    mkdir -p /home/user/hailstone_ffi/rust_src/src

    cat << 'EOF' > /home/user/hailstone_ffi/c_src/fast_math.c
#include <stdint.h>
uint64_t next_hailstone(uint64_t n) {
    if (n % 2 == 0) return n / 2;
    return 3 * n + 1;
}
EOF

    cat << 'EOF' > /home/user/hailstone_ffi/c_src/fast_math.h
#include <stdint.h>
uint64_t next_hailstone(uint64_t n);
EOF

    cat << 'EOF' > /home/user/hailstone_ffi/c_src/Makefile
all: libfastmath.a

libfastmath.a: fast_math.o
	gcc -o libfastmath.a fast_math.o  # BUG: Should be ar rcs libfastmath.a fast_math.o

fast_math.o: fast_math.c
	gcc -c -O3 fast_math.c -o fast_math.o

clean:
	rm -f *.o *.a
EOF

    cat << 'EOF' > /home/user/hailstone_ffi/rust_src/Cargo.toml
[package]
name = "hailstone_rust"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/hailstone_ffi/rust_src/src/lib.rs
// Skeleton
EOF

    cat << 'EOF' > /home/user/hailstone_ffi/rust_src/src/main.rs
// Skeleton
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
