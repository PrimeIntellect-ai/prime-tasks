#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user
    cargo new math_processor
    cd math_processor

    cat << 'EOF' > src/main.rs
use std::fs;

const SECRET: u64 = 987654321;

fn compute_sequence(n: usize) -> u64 {
    if n == 0 { return 0; }
    if n == 1 { return 1; }
    let mut a: u64 = 0;
    let mut b: u64 = 1;
    for _ in 2..=n {
        let next = b * SECRET + a;
        a = b;
        b = next;
    }
    b
}

fn main() {
    let inputs = fs::read_to_string("inputs.txt").unwrap();
    let mut results = Vec::new();
    for line in inputs.lines() {
        if let Ok(n) = line.trim().parse::<usize>() {
            let res = compute_sequence(n);
            results.push(format!("Input: {}, Output: {}", n, res));
        }
    }
    fs::write("/home/user/output.txt", results.join("\n")).unwrap();
}
EOF

    git config --global user.email "dev@example.com"
    git config --global user.name "Dev"

    git init
    git add .
    git commit -m "Initial commit with working math sequence"

    sed -i 's/const SECRET: u64 = 987654321;/const SECRET: u64 = 0;/g' src/main.rs
    git add src/main.rs
    git commit -m "Remove secret from source code"

    cat << 'EOF' > inputs.txt
10
50
100
EOF
    git add inputs.txt
    git commit -m "Add inputs file"

    chmod -R 777 /home/user
