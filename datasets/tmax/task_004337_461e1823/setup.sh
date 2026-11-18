#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc rustc
    pip3 install pytest

    mkdir -p /home/user/release_prep/c_src
    mkdir -p /home/user/release_prep/rust_src
    mkdir -p /home/user/release_prep/python_src

    cat << 'EOF' > /home/user/release_prep/c_src/math_core.c
#include <stdlib.h>
#include <stdio.h>

// Calculates the cumulative sum of an array.
// BUG: There is an off-by-one buffer overflow here causing Undefined Behavior.
void cumsum(double* input, double* output, int n) {
    double current_sum = 0.0;
    for (int i = 0; i <= n; i++) {
        current_sum += input[i];
        output[i] = current_sum;
    }
}
EOF

    cat << 'EOF' > /home/user/release_prep/rust_src/validator.rs
fn calculate_hash(data: String) -> usize {
    data.len() * 42
}

fn main() {
    let report = String::from("Release Candidate 1");
    let hash_val = calculate_hash(report);
    // BUG: borrow checker error here because `report` was moved.
    println!("Report: {} has hash: {}", report, hash_val);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
