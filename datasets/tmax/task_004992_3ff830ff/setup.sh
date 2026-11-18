#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest jupyter nbconvert nbformat

    # Install Rust globally
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/cargo/bin:$PATH"

    # Create directories
    mkdir -p /home/user/data /home/user/results

    # Create FASTA file
    cat << 'EOF' > /home/user/data/sequence.fasta
>seq1
GGCCTTAAGGCCTTAAGGCCTTAAGGCCTTAAGGCCTTAAGGCCTTAAGGCCTTAAGGCCTTAAGGCCTTAAGGCCTTAA
EOF

    # Create Rust project
    cd /home/user
    cargo new mutator
    cd mutator
    cargo add rand --features std
    cargo add rand_chacha

    # Populate main.rs
    cat << 'EOF' > /home/user/mutator/src/main.rs
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;
use std::fs;

fn main() {
    let mut p_count = 0;
    let iterations = 10000;
    let seed: [u8; 32] = [42; 32];

    for _ in 0..iterations {
        // BOTTLENECK & LOGIC FLAW: Reading file and resetting RNG inside the loop
        let fasta = fs::read_to_string("/home/user/data/sequence.fasta").unwrap();
        let original_seq: String = fasta.lines().skip(1).collect();
        let mut seq: Vec<char> = original_seq.chars().collect();

        let mut rng = ChaCha8Rng::from_seed(seed);
        let idx = rng.gen_range(0..seq.len());
        seq[idx] = 'A';

        // Check if 'A' count increased
        if seq.iter().filter(|&&c| c == 'A').count() > original_seq.chars().filter(|&c| c == 'A').count() {
            p_count += 1;
        }
    }

    let p_value = p_count as f64 / iterations as f64;
    fs::write("/home/user/results/output.txt", format!("p_value: {}", p_value)).unwrap();
}
EOF

    # Create Jupyter Notebook
    cat << 'EOF' > /home/user/make_nb.py
import nbformat as nbf
nb = nbf.v4.new_notebook()
code = """
import subprocess
import os

# Run the Rust binary
subprocess.run(["/home/user/mutator/target/release/mutator"], check=True)

# Read the output and write the summary
with open("/home/user/results/output.txt", "r") as f:
    data = f.read().strip()

with open("/home/user/results/summary.txt", "w") as f:
    f.write(f"Workflow Complete. Result -> {data}")
"""
nb['cells'] = [nbf.v4.new_code_cell(code)]
nbf.write(nb, '/home/user/workflow.ipynb')
EOF
    python3 /home/user/make_nb.py
    rm /home/user/make_nb.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /opt/rust /opt/cargo
    chmod -R 777 /home/user
