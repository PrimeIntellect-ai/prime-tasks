#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    export PATH=/usr/local/cargo/bin:$PATH

    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    rustup target add wasm32-unknown-unknown
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME

    mkdir -p /home/user/workspace/rusty_math/src

    cat << 'EOF' > /home/user/workspace/rusty_math/Cargo.toml
[package]
name = "rusty_math"
version = "0.1.0"
edition = "2021"

[dependencies]
num-traits = "0.2.19"
EOF

    cat << 'EOF' > /home/user/workspace/rusty_math/src/lib.rs
use num_traits::Zero;

pub fn compute_algorithm() -> u32 {
    let start = std::time::Instant::now();
    let mut result: u32 = Zero::zero();
    for i in 0..10 {
        result += i;
    }
    println!("Elapsed: {:?}", start.elapsed());
    result + 42 - 45
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
