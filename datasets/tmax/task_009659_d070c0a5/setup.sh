#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest numpy

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    # Setup the environment and the buggy Rust project
    mkdir -p /home/user/sim_project/src
    cd /home/user/sim_project

    cat << 'EOF' > Cargo.toml
[package]
name = "sim_project"
version = "0.1.0"
edition = "2021"

[dependencies]
rayon = "1.8"
EOF

    cat << 'EOF' > src/main.rs
use rayon::prelude::*;
use std::sync::{Arc, Mutex};

fn solve_ode(y0: f64) -> f64 {
    let mut y = y0;
    let dt = 0.1;
    for _ in 0..100 {
        // dy/dt = -0.1 * y
        y += -0.1 * y * dt;
    }
    y
}

fn main() {
    let results = Arc::new(Mutex::new(Vec::new()));

    (0..5000).into_par_iter().for_each(|i| {
        let y0 = i as f64;
        let res = solve_ode(y0);
        results.lock().unwrap().push(res);
    });

    let final_results = results.lock().unwrap();
    for r in final_results.iter() {
        println!("{}", r);
    }
}
EOF

    # Make rustc and cargo available for all users
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup

    useradd -m -s /bin/bash user || true

    # Ensure environment variables are set for user
    echo 'export PATH="/home/user/.cargo/bin:$PATH"' >> /home/user/.bashrc

    chmod -R 777 /home/user
