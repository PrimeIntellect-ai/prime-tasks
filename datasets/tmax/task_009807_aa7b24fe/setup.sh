#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo bc
pip3 install pytest

mkdir -p /home/user/sim_project/src
cat << 'EOF' > /home/user/sim_project/Cargo.toml
[package]
name = "sim_project"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /home/user/sim_project/src/main.rs
use std::fs;
use std::io::Write;

fn main() {
    let edges_str = fs::read_to_string("/home/user/molecule.txt").unwrap();
    let num_nodes = 5;
    let mut adj = vec![vec![0.0; num_nodes]; num_nodes];
    let mut deg = vec![0.0; num_nodes];
    for line in edges_str.lines() {
        let parts: Vec<usize> = line.split_whitespace().map(|s| s.parse().unwrap()).collect();
        adj[parts[0]][parts[1]] = 1.0;
        adj[parts[1]][parts[0]] = 1.0;
        deg[parts[0]] += 1.0;
        deg[parts[1]] += 1.0;
    }

    let mut trans = vec![vec![0.0; num_nodes]; num_nodes];
    for i in 0..num_nodes {
        for j in 0..num_nodes {
            // BUG: Unstable transition matrix
            trans[i][j] = adj[i][j] * 1.5;
        }
    }

    let mut state = vec![1.0, 0.0, 0.0, 0.0, 0.0];
    let mut signal = Vec::new();

    for _ in 0..100 {
        signal.push(state[0]);
        let mut next_state = vec![0.0; num_nodes];
        for i in 0..num_nodes {
            for j in 0..num_nodes {
                next_state[j] += state[i] * trans[i][j];
            }
        }
        state = next_state;
    }

    let mut out = fs::File::create("/home/user/sim_project/signal.txt").unwrap();
    for val in signal {
        writeln!(out, "{:.4}", val).unwrap();
    }
}
EOF

cat << 'EOF' > /home/user/molecule.txt
0 1
1 2
2 3
3 4
4 0
0 2
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/sim_project
chown user:user /home/user/molecule.txt
chmod -R 777 /home/user
