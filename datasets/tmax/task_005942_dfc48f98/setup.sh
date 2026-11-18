#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /home/user/math_polyglot/rust_math/src
    mkdir -p /home/user/math_polyglot/python_e2e

    cat << 'EOF' > /home/user/math_polyglot/rust_math/Cargo.toml
[package]
name = "rust_math"
version = "0.1.0"
edition = "2021"

[lib]
EOF

    cat << 'EOF' > /home/user/math_polyglot/rust_math/src/lib.rs
pub extern "C" fn fast_fib(n: u32) -> u64 {
    if n == 0 { return 0; }
    if n == 1 { return 1; }
    let mut a: u64 = 0;
    let mut b: u64 = 1;
    for _ in 2..=n {
        let temp = a.wrapping_add(b);
        a = b;
        b = temp;
    }
    b
}
EOF

    cat << 'EOF' > /home/user/math_polyglot/python_e2e/test_fib.py
import ctypes
import os
import sys

def run_test():
    lib_path = "/home/user/math_polyglot/rust_math/target/release/librust_math.so"
    if not os.path.exists(lib_path):
        print(f"Library not found at {lib_path}")
        sys.exit(1)

    math_lib = ctypes.CDLL(lib_path)
    math_lib.fast_fib.argtypes = [ctypes.c_uint32]

    # BUG: restype is incorrectly set to 32-bit integer, causing truncation of the 64-bit result
    math_lib.fast_fib.restype = ctypes.c_uint32 

    result = math_lib.fast_fib(93)
    expected = 12200160415121876738

    if result == expected:
        with open("/home/user/e2e_success.log", "w") as f:
            f.write(f"SUCCESS: {result}")
        print("E2E Test Passed")
    else:
        print(f"FAILED: Expected {expected}, got {result}")
        sys.exit(1)

if __name__ == "__main__":
    run_test()
EOF

    useradd -m -s /bin/bash user || true
    # Ensure rustup is available for user
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup
    chown -R user:user /home/user/.cargo /home/user/.rustup

    chmod -R 777 /home/user
