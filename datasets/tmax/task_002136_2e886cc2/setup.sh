#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential golang cargo rustc
    pip3 install pytest

    mkdir -p /home/user/rust_lib/src
    cat << 'EOF' > /home/user/rust_lib/Cargo.toml
[package]
name = "rust_lib"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    cat << 'EOF' > /home/user/rust_lib/src/lib.rs
#[no_mangle]
pub extern "C" fn poly_eval(coeffs: *const f64, len: usize, x: f64) -> f64 {
    if coeffs.is_null() || len == 0 {
        return 0.0;
    }
    let slice = unsafe { std::slice::from_raw_parts(coeffs, len) };

    let mut results = vec![];
    results.push(slice[0]);
    let first_ref = &results[0]; // Causes borrow checker error below

    for i in 1..len {
        results.push(results[i-1] * x + slice[i]);
    }

    *first_ref - slice[0] + results[len-1]
}
EOF

    mkdir -p /home/user/go_app
    cd /home/user/go_app
    go mod init go_app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
