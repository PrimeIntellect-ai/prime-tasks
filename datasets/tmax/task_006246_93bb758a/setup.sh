#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential libopenblas-dev pkg-config cargo rustc
    pip3 install pytest

    mkdir -p /home/user/stiff_ode/src
    cd /home/user/stiff_ode

    cat << 'EOF' > Cargo.toml
[package]
name = "stiff_ode"
version = "0.1.0"
edition = "2021"

[dependencies]
ndarray = "0.15"
ndarray-linalg = { version = "0.16", features = ["openblas-system"] }
csv = "1.1"
EOF

    cat << 'EOF' > src/main.rs
use ndarray::{Array1, Array2};
use ndarray_linalg::Solve;
use std::fs;

fn main() {
    // Read Matrix A
    let a_str = fs::read_to_string("matrix_A.txt").unwrap();
    let mut a_vec = Vec::new();
    let mut rows = 0;
    for line in a_str.lines() {
        let parts: Vec<f64> = line.split(',').map(|s| s.parse().unwrap()).collect();
        a_vec.extend(parts);
        rows += 1;
    }
    let cols = a_vec.len() / rows;
    let a = Array2::from_shape_vec((rows, cols), a_vec).unwrap();

    // Read Vector b
    let b_str = fs::read_to_string("vector_b.txt").unwrap();
    let b_vec: Vec<f64> = b_str.trim().split(',').map(|s| s.parse().unwrap()).collect();
    let b = Array1::from_vec(b_vec);

    // Buggy LU solve
    let x = a.solve(&b).expect("Failed to solve linear system");

    // Write output
    let out_strs: Vec<String> = x.iter().map(|v| format!("{:.4}", v)).collect();
    fs::write("solution.txt", out_strs.join(",")).unwrap();
}
EOF

    cat << 'EOF' > matrix_A.txt
1.0,-1.0,0.0,0.0
-1.0,2.0,-1.0,0.0
0.0,-1.0,2.0,-1.0
0.0,0.0,-1.0,1.0
EOF

    cat << 'EOF' > vector_b.txt
1.0,-1.0,-1.0,1.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
