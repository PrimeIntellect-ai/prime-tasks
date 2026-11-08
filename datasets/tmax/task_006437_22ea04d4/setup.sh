#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl build-essential
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    export PATH=/opt/rust/bin:$PATH

    useradd -m -s /bin/bash user || true

    cd /home/user
    cargo new math_toolkit
    cd math_toolkit

    cat << 'EOF' > Cargo.toml
[package]
name = "math_toolkit"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > src/lib.rs
use serde::Deserialize;

#[derive(Deserialize)]
pub struct InputData {
    pub numbers: Vec<u64>,
}

pub fn collatz_length(mut n: u64) -> u64 {
    if n == 1 {
        return 0;
    }
    if n % 2 == 0 {
        1 + collatz_length(n / 2)
    } else {
        // Bug: infinite recursion / wrong formula
        1 + collatz_length(n + 1)
    }
}

pub fn calculate_stats(numbers: &[u64]) -> Vec<u64> {
    let mut stats = Vec::new();
    for &n in numbers {
        // Bug: assertion failure
        assert!(n < 100, "Number too large!");
        stats.push(collatz_length(n));
    }
    stats
}

// Compile error
pub fn compile_error_fn() {
    let x: u32 = "string";
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_collatz() {
        assert_eq!(collatz_length(15), 17);
    }
}
EOF

    cat << 'EOF' > src/main.rs
use math_toolkit::{InputData, calculate_stats};
use std::fs;

fn main() {
    let data = fs::read_to_string("inputs.json").expect("Failed to read inputs.json");
    let input: InputData = serde_json::from_str(&data).expect("Failed to parse JSON");
    let stats = calculate_stats(&input.numbers);
    for (i, &n) in input.numbers.iter().enumerate() {
        println!("Number: {}, Collatz Length: {}", n, stats[i]);
    }
}
EOF

    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    git add .
    git commit -m "Initial commit"

    # Create dangling blob
    git hash-object -w /dev/stdin << 'EOF'
{
    "numbers": [15, 27,, 42, 99, 1000, "GARBAGE"]
}
EOF

    # Fix permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /opt/rust
