#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    mkdir -p /home/user/pdb_feature_extractor/src

    cat << 'EOF' > /home/user/pdb_feature_extractor/Cargo.toml
[package]
name = "pdb_feature_extractor"
version = "0.1.0"
edition = "2021"

[dependencies]
nalgebra = "0.32"
EOF

    cat << 'EOF' > /home/user/pdb_feature_extractor/src/main.rs
use nalgebra::{Matrix3, Point3};
use std::fs::File;
use std::io::{BufRead, BufReader};

fn main() {
    let file = File::open("/home/user/input.pdb").unwrap();
    let reader = BufReader::new(file);
    let mut points = Vec::new();

    for line in reader.lines() {
        let line = line.unwrap();
        if line.starts_with("ATOM  ") || line.starts_with("HETATM") {
            let x: f64 = line[30..38].trim().parse().unwrap();
            let y: f64 = line[38..46].trim().parse().unwrap();
            let z: f64 = line[46..54].trim().parse().unwrap();
            points.push(Point3::new(x, y, z));
        }
    }

    let n = points.len() as f64;
    let mut mean = Point3::new(0.0, 0.0, 0.0);
    for p in &points {
        mean.x += p.x;
        mean.y += p.y;
        mean.z += p.z;
    }
    mean.x /= n;
    mean.y /= n;
    mean.z /= n;

    let mut cov = Matrix3::zeros();
    for p in &points {
        let dx = p.x - mean.x;
        let dy = p.y - mean.y;
        let dz = p.z - mean.z;
        cov[(0, 0)] += dx * dx;
        cov[(0, 1)] += dx * dy;
        cov[(0, 2)] += dx * dz;
        cov[(1, 0)] += dy * dx;
        cov[(1, 1)] += dy * dy;
        cov[(1, 2)] += dy * dz;
        cov[(2, 0)] += dz * dx;
        cov[(2, 1)] += dz * dy;
        cov[(2, 2)] += dz * dz;
    }
    cov /= n;

    // BUG: This will panic for planar molecules!
    let cholesky = cov.cholesky().unwrap();
    let l = cholesky.l();

    let trace = l[(0,0)] + l[(1,1)] + l[(2,2)];
    println!("Trace: {}", trace);
}
EOF

    cat << 'EOF' > /home/user/input.pdb
ATOM      1  C   MOL     1       1.000   0.000   0.000  1.00  0.00           C
ATOM      2  C   MOL     1       0.000   1.000   0.000  1.00  0.00           C
ATOM      3  C   MOL     1      -1.000   0.000   0.000  1.00  0.00           C
ATOM      4  C   MOL     1       0.000  -1.000   0.000  1.00  0.00           C
EOF

    # Pre-build to download crates
    cd /home/user/pdb_feature_extractor
    cargo build || true

    # Make rust available for all users
    cp -r /root/.cargo /usr/local/cargo
    cp -r /root/.rustup /usr/local/rustup

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
