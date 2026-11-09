#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/sim_tracker/src

    cat << 'EOF' > /home/user/sim_tracker/Cargo.toml
[package]
name = "sim_tracker"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/sim_tracker/src/lib.rs
pub fn run_simulation(seed: u64) -> Result<f64, String> {
    let mut state: f32 = 1000.0;
    let perturbation = (seed % 15) as f32;

    for i in 0..50000 {
        // Precision loss: adding extremely small values to a large f32
        let step = 1.0 / (perturbation + i as f32 + 1.0);
        let previous_state = state;
        state += step;

        // If state stops growing despite adding a positive step, precision is lost
        if state == previous_state {
            return Err(format!("Numerical instability detected at iteration {}", i));
        }
    }

    Ok(state as f64)
}
EOF

    cat << 'EOF' > /home/user/sim_tracker/src/main.rs
use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <seed>", args[0]);
        std::process::exit(1);
    }

    let seed: u64 = args[1].parse().unwrap();
    let result = sim_tracker::run_simulation(seed);

    // INTENTIONAL COMPILER ERROR: trying to format a Result without Debug/unwrap
    println!("Simulation result: {}", result);
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/sim_tracker
    chmod -R 777 /home/user
