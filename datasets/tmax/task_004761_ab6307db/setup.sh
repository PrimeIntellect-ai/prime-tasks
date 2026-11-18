#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    # Create directories
    mkdir -p /home/user/primer_opt/src /home/user/data /home/user/output

    # Create sequences.txt
    cat << 'EOF' > /home/user/data/sequences.txt
ATGCGTACGTAGCTAGCTAGCTAGCTAG
CGTAGCTAGCTAGCTAGCTAGCTAGCTA
GCTAGCTAGCTAGCTAGCTAGCTAGCTA
EOF

    # Create Cargo.toml
    cat << 'EOF' > /home/user/primer_opt/Cargo.toml
[package]
name = "primer_opt"
version = "0.1.0"
edition = "2021"

[dependencies]
nalgebra = "0.32"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    # Create main.rs
    cat << 'EOF' > /home/user/primer_opt/src/main.rs
use nalgebra::{DMatrix, DVector};
use serde::Serialize;
use std::fs;

#[derive(Serialize)]
struct PrimerResult {
    sequence_id: usize,
    params: Vec<f64>,
    final_score: f64,
}

fn compute_residual(params: &DVector<f64>) -> DVector<f64> {
    // Dummy non-linear residual: r_i = x_i^2 - 2.0
    let mut r = DVector::zeros(params.len());
    for i in 0..params.len() {
        r[i] = params[i].powi(2) - 2.0;
    }
    r
}

fn compute_jacobian(params: &DVector<f64>) -> DMatrix<f64> {
    // J_ij = d(r_i)/d(x_j) = 2 * x_i if i == j else 0
    let mut j = DMatrix::zeros(params.len(), params.len());
    for i in 0..params.len() {
        j[(i, i)] = 2.0 * params[i];
    }
    // Intentionally make it near-singular by zeroing out the last row
    let n = params.len();
    for c in 0..n {
        j[(n-1, c)] = 1e-12; // near singular
    }
    j
}

fn main() {
    let num_seqs = 3;
    let mut results = Vec::new();

    for seq_id in 0..num_seqs {
        let mut params = DVector::from_vec(vec![1.5, 0.5, 1.0]);
        let max_iter = 10;

        for _ in 0..max_iter {
            let r = compute_residual(&params);
            let j = compute_jacobian(&params);

            let j_t = j.transpose();
            let j_t_j = &j_t * &j;
            let j_t_r = &j_t * &r;

            // BUG: j_t_j is near singular.
            // AGENT FIX: let j_t_j = j_t_j + DMatrix::identity(3, 3) * 1e-3;

            let delta = j_t_j.cholesky().expect("Matrix factorization failed due to near-singularity").solve(&j_t_r);
            params -= delta;
        }

        let final_score = compute_residual(&params).norm();
        results.push(PrimerResult {
            sequence_id: seq_id,
            params: params.iter().cloned().collect(),
            final_score,
        });
    }

    let json = serde_json::to_string_pretty(&results).unwrap();
    fs::write("/home/user/output/optimized_primers.json", json).unwrap();
}
EOF

    # Create user
    useradd -m -s /bin/bash user || true

    # Install rust for user as well, or just make cargo available globally
    # To make it available for the user:
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust
    ln -s /opt/rust/bin/* /usr/local/bin/

    # Set permissions
    chmod -R 777 /home/user
