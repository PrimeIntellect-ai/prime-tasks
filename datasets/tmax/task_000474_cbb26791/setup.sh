#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest grpcio grpcio-tools

    # Install Rust system-wide
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust
    ln -s /opt/rust/bin/* /usr/local/bin/

    # Create directories
    mkdir -p /home/user/proto /home/user/legacy /home/user/server /home/user/rust_lib/src

    # Create legacy JavaScript file
    cat << 'EOF' > /home/user/legacy/calc.js
function compute_base(data) { // data is an array of bytes
    let sig = 0;
    for (let i = 0; i < data.length; i++) {
        sig = (sig * 31 + data[i]) % 1000000007;
    }
    return sig;
}
EOF

    # Create Rust Cargo.toml
    cat << 'EOF' > /home/user/rust_lib/Cargo.toml
[package]
name = "rust_lib"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]
EOF

    # Create Rust lib.rs with the bug
    cat << 'EOF' > /home/user/rust_lib/src/lib.rs
#[no_mangle]
pub extern "C" fn process_signature(base: u64) -> u64 {
    let vec1 = vec![base];
    let vec2 = vec1;
    let _vec3 = vec1; // ERROR: use of moved value: `vec1`

    let mut res = vec2[0];
    res = (res ^ 0xDEADBEEF) % 9999991;
    res
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
