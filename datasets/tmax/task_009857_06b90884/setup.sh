#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        git \
        strace \
        cargo \
        rustc

    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # 1. Create the container log
    cat << 'EOF' > /home/user/container_crash.log
[FATAL] Simulation diverged at iteration 1000!
[DEBUG] Expected final state: > 0.600
[DEBUG] Actual final state: 0.1983
[INFO] Simulation parameters: r=3.99, x0=0.5
[ERROR] Aborting sequence.
EOF

    # 2. Create the Rust project and binary
    mkdir -p /home/user/math_repo
    cd /home/user/math_repo

    cargo init --bin .

    cat << 'EOF' > src/main.rs
use std::fs;

fn main() {
    let config = fs::read_to_string("/tmp/sim_config.txt").unwrap_or_else(|_| {
        std::process::exit(1);
    });
    let parts: Vec<&str> = config.trim().split_whitespace().collect();
    if parts.len() != 2 { std::process::exit(1); }

    let r: f64 = parts[0].parse().unwrap();
    let mut x: f64 = parts[1].parse().unwrap();

    for _ in 0..1000 {
        x = r * x * (1.0 - x);
    }

    println!("{:.4}", x);
    if x < 0.6 {
        std::process::exit(2);
    }
}
EOF

    # Build initial good binary
    cargo build --release
    cp target/release/math_repo /home/user/prod_bin_good

    # Git setup
    git config --global user.email "dev@example.com"
    git config --global user.name "Dev"
    git init
    git add .
    git commit -m "Initial commit"

    # Generate 200 commits. Introduce the bug at commit 137.
    for i in $(seq 1 200); do
        if [ $i -eq 137 ]; then
            # Introduce precision bug (f64 -> f32)
            sed -i 's/f64/f32/g' src/main.rs
            git add src/main.rs
            git commit -m "Commit $i: Optimize memory usage for simulation"
            BAD_COMMIT=$(git rev-parse HEAD)
        else
            # Dummy changes
            echo "// Dummy comment $i" >> src/main.rs
            git add src/main.rs
            git commit -m "Commit $i: Minor update"
        fi
    done

    # Build bad binary
    cargo build --release
    cp target/release/math_repo /home/user/prod_bin

    # Save the bad commit hash for verification
    echo "$BAD_COMMIT" > /home/user/.secret_bad_commit

    # Clean up target dir so agent has to rebuild
    cargo clean

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
