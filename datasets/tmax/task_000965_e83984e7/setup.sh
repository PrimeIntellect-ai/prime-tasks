#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sec-payload-verifier/src

    cat << 'EOF' > /home/user/sec-payload-verifier/Cargo.toml
[package]
name = "sec-payload-verifier"
version = "0.1.0"
edition = "2021"

[build-dependencies]
cc = "1.0"

[dev-dependencies]
proptest = "1.0"
EOF

    cat << 'EOF' > /home/user/sec-payload-verifier/src/fast_chk.c
#include <stdint.h>
#include <stddef.h>

uint32_t compute_fast_chk(const uint8_t* data, size_t len) {
    uint32_t chk = 0xAA55AA55;
    for (size_t i = 0; i < len; i++) {
        chk ^= data[i];
        chk = (chk << 1) | (chk >> 31);
    }
    return chk;
}
EOF

    cat << 'EOF' > /home/user/sec-payload-verifier/src/lib.rs
extern "C" {
    fn compute_fast_chk(data: *const u8, len: usize) -> u32;
}

pub fn verify_payload(data: &[u8]) -> u32 {
    unsafe { compute_fast_chk(data.as_ptr(), data.len()) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    // Rust reference implementation for the property test
    fn rust_chk(data: &[u8]) -> u32 {
        let mut chk = 0xAA55AA55u32;
        for &b in data {
            chk ^= b as u32;
            chk = chk.rotate_left(1);
        }
        chk
    }

    proptest! {
        #[test]
        fn test_ffi_checksum_matches_rust(data in proptest::collection::vec(any::<u8>(), 0..100)) {
            let c_res = verify_payload(&data);
            let r_res = rust_chk(&data);
            assert_eq!(c_res, r_res);
        }
    }
}
EOF

    cat << 'EOF' > /home/user/sec-payload-verifier/build.rs
fn main() {
    // TODO: Compile src/fast_chk.c and link it.
}
EOF

    chmod -R 777 /home/user
