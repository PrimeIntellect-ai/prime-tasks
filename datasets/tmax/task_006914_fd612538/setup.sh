#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils cargo rustc
pip3 install pytest

# Create directories
mkdir -p /home/user/clib
mkdir -p /home/user/rust-linker-debug/src

# Create the C library
cat << 'EOF' > /home/user/clib/ops.c
int ops_mul_v2(int a, int b, int flags) {
    if (flags == 1) return a * b * -1;
    return a * b;
}
EOF
gcc -c /home/user/clib/ops.c -o /home/user/clib/ops.o
ar rcs /home/user/clib/libops.a /home/user/clib/ops.o

# Create the manifest
cat << 'EOF' > /home/user/clib/manifest.json
{
  "name": "libops",
  "version": "2.1.3",
  "cflags": "-I/home/user/clib/include",
  "libs": "-L/home/user/clib -lops"
}
EOF

# Create the Rust project files
cat << 'EOF' > /home/user/rust-linker-debug/Cargo.toml
[package]
name = "rust-linker-debug"
version = "0.1.0"
edition = "2021"

[dependencies]

[build-dependencies]
semver = "1.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"

[dev-dependencies]
proptest = "1.0"
EOF

cat << 'EOF' > /home/user/rust-linker-debug/build.rs
use std::fs;

fn main() {
    println!("cargo:rustc-link-search=native=/home/user/clib");
    println!("cargo:rustc-link-lib=static=ops");

    // Agent needs to add JSON parsing and semver check here
}
EOF

cat << 'EOF' > /home/user/rust-linker-debug/src/lib.rs
extern "C" {
    fn ops_mul(a: i32, b: i32) -> i32;
    // Agent needs to conditionally define ops_mul_v2 here
}

pub fn safe_mul(a: i32, b: i32) -> i32 {
    unsafe {
        // Agent needs to conditionally call ops_mul or ops_mul_v2
        ops_mul(a, b)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    // Agent needs to add proptest here
}
EOF

# Create the user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
