#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/protein_network/src
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/protein_network/Cargo.toml
[package]
name = "protein_network"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/protein_network/src/main.rs
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader};

#[derive(Clone)]
struct Atom {
    chain: char,
    res_num: i32,
    x: f64,
    y: f64,
    z: f64,
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <pdb_file>", args[0]);
        return;
    }

    let file = File::open(&args[1]).unwrap();
    let reader = BufReader::new(file);
    let mut atoms = Vec::new();

    for line in reader.lines() {
        let line = line.unwrap();
        if line.starts_with("ATOM  ") && &line[12..16] == " CA " {
            let chain = line.chars().nth(21).unwrap();
            let res_num: i32 = line[22..26].trim().parse().unwrap();
            let x: f64 = line[30..38].trim().parse().unwrap();
            let y: f64 = line[38..46].trim().parse().unwrap();
            let z: f64 = line[46..54].trim().parse().unwrap();
            atoms.push(Atom { chain, res_num, x, y, z });
        }
    }

    let n = atoms.len();
    let mut adjacency = vec![vec![0.0; n]; n];

    // TODO: parallelize this
    for i in 0..n {
        for j in 0..n {
            if i != j {
                let dx = atoms[i].x - atoms[j].x;
                let dy = atoms[i].y - atoms[j].y;
                let dz = atoms[i].z - atoms[j].z;
                let dist = (dx * dx + dy * dy + dz * dz).sqrt();
                if dist <= 8.0 {
                    adjacency[i][j] = 1.0;
                }
            }
        }
    }

    let mut transition = vec![vec![0.0; n]; n];
    for i in 0..n {
        let mut degree = 0.0;
        for j in 0..n {
            degree += adjacency[j][i];
        }
        if degree > 0.0 {
            for j in 0..n {
                transition[j][i] = adjacency[j][i] / degree;
            }
        }
    }

    let mut v = vec![1.0 / n as f64; n];

    // Power iteration - currently unstable
    for _ in 0..100 {
        let mut next_v = vec![0.0; n];
        for i in 0..n {
            for j in 0..n {
                next_v[i] += transition[i][j] * v[j];
            }
        }
        v = next_v;
    }

    let mut scores: Vec<(usize, f64)> = v.into_iter().enumerate().collect();
    scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());

    for i in 0..3 {
        let idx = scores[i].0;
        println!("{}:{}", atoms[idx].chain, atoms[idx].res_num);
    }
}
EOF

    cat << 'EOF' > /home/user/data/complex.pdb
ATOM      1  CA  ALA A   1      10.000  10.000  10.000  1.00 10.00           C  
ATOM      2  CA  CYS A   2      14.000  10.000  10.000  1.00 10.00           C  
ATOM      3  CA  ASP A   3      14.000  14.000  10.000  1.00 10.00           C  
ATOM      4  CA  GLU A   4      10.000  14.000  10.000  1.00 10.00           C  
ATOM      5  CA  PHE B   1      50.000  50.000  50.000  1.00 10.00           C  
ATOM      6  CA  GLY B   2      54.000  50.000  50.000  1.00 10.00           C  
ATOM      7  CA  HIS B   3      54.000  54.000  50.000  1.00 10.00           C  
ATOM      8  CA  ILE B   4      50.000  54.000  50.000  1.00 10.00           C  
ATOM      9  CA  LYS B   5      52.000  52.000  50.000  1.00 10.00           C  
EOF

    chown -R user:user /home/user/protein_network /home/user/data
    chmod -R 777 /home/user
