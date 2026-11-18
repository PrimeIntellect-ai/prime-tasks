#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest numpy

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/rust/bin:$PATH"

    # Create vendored Rust crate
    mkdir -p /app/diffusion_sim/src

    cat << 'EOF' > /app/diffusion_sim/Cargo.toml
[package]
name = "diffusion_sim"
version = "0.1.0"
edition = "2021"

[dependencies]
rustfft = "6.1.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /app/diffusion_sim/src/main.rs
use rustfft::{FftPlanner, num_complex::Complex};
use std::f64::consts::PI;
use std::fs::File;

fn main() {
    let n = 256;
    let nu = 0.1;
    let dt = 0.001;
    let steps = 1000;

    let mut planner = FftPlanner::new();
    let fft = planner.plan_fft_forward(n);
    let ifft = planner.plan_fft_inverse(n);

    let mut u: Vec<Complex<f64>> = (0..n).map(|i| {
        let x = 2.0 * PI * (i as f64) / (n as f64);
        Complex::new(x.sin() + 0.5 * (3.0 * x).sin(), 0.0)
    }).collect();

    fft.process(&mut u);

    for _ in 0..steps {
        for k in 0..n {
            let k_val = if k < n / 2 { k as f64 } else { (k as f64) - (n as f64) };
            // BUG: incorrectly implemented spectral derivative
            let multiplier = -nu * k_val;
            u[k] = u[k] * Complex::new(f64::exp(multiplier * dt), 0.0);
        }
    }

    ifft.process(&mut u);
    let final_u: Vec<f64> = u.iter().map(|c| c.re / (n as f64)).collect();

    let file = File::create("/home/user/final_state.json").expect("Failed to create file");
    serde_json::to_writer(file, &final_u).expect("Failed to write JSON");
}
EOF

    # Pre-fetch dependencies
    cd /app/diffusion_sim && cargo fetch

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
