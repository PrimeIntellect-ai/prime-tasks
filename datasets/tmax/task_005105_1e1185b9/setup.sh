#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/fitter/src

    # Create sequence.fasta
    cat << 'EOF' > /home/user/data/sequence.fasta
>protein_seq
ARNDCEQGHILKMFPSTWYV
EOF

    # Create structure.pdb
    cat << 'EOF' > /home/user/data/structure.pdb
ATOM      1  N   ALA A   1      11.104   6.134  -6.504  1.00 20.00           N  
ATOM      2  CA  ALA A   1      11.639   6.071  -5.147  1.00 20.50           C  
ATOM      3  C   ALA A   1      10.636   6.673  -4.135  1.00 21.00           C  
ATOM      4  N   ARG A   2       9.356   6.309  -4.305  1.00 22.00           N  
ATOM      5  CA  ARG A   2       8.283   6.804  -3.468  1.00 23.50           C  
ATOM      6  N   ASN A   3       7.567   7.930  -2.100  1.00 24.00           N  
ATOM      7  CA  ASN A   3       6.155   8.266  -2.311  1.00 26.50           C  
ATOM      8  N   ASP A   4       4.520   6.745  -1.020  1.00 28.00           N  
ATOM      9  CA  ASP A   4       3.322   6.166  -1.633  1.00 29.50           C  
ATOM     10  N   CYS A   5       2.120   5.111  -2.220  1.00 31.00           N  
ATOM     11  CA  CYS A   5       1.000   4.222  -2.888  1.00 32.50           C  
EOF

    # Create Rust project
    cat << 'EOF' > /home/user/fitter/Cargo.toml
[package]
name = "fitter"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.1"
serde = { version = "1.0", features = ["derive"] }
EOF

    cat << 'EOF' > /home/user/fitter/src/main.rs
use std::env;
use std::error::Error;
use std::fs::File;
use csv::ReaderBuilder;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Record {
    index: f64,
    fasta_char: String,
    pdb_res_name: String,
    b_factor: f64,
}

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <dataset.csv>", args[0]);
        std::process::exit(1);
    }

    let file = File::open(&args[1])?;
    let mut rdr = ReaderBuilder::new().from_reader(file);

    let mut indices = Vec::new();
    let mut b_factors = Vec::new();

    for result in rdr.deserialize() {
        let record: Record = result?;
        indices.push(record.index);
        b_factors.push(record.b_factor);
    }

    let n = indices.len() as f64;
    let mut alpha = 0.0;
    let mut beta = 0.0;

    // BUG: Step size (learning rate) is way too high, causing divergence
    let lr = 0.5;
    let epochs = 50000;

    for _ in 0..epochs {
        let mut d_alpha = 0.0;
        let mut d_beta = 0.0;

        for i in 0..indices.len() {
            let x = indices[i];
            let y = b_factors[i];
            let pred = alpha + beta * x;
            let error = pred - y;

            d_alpha += error;
            d_beta += error * x;
        }

        alpha -= lr * (d_alpha / n);
        beta -= lr * (d_beta / n);
    }

    println!("alpha: {:.4}", alpha);
    println!("beta: {:.4}", beta);

    Ok(())
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
