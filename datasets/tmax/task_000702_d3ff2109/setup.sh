#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    mkdir -p /home/user/sim_engine

    cat << 'EOF' > /home/user/sim_engine/sim.rs
use std::fs::File;
use std::io::Write;
use std::f64::consts::PI;

fn main() {
    let mut file = File::create("/home/user/trace.csv").unwrap();
    let k_true = 0.8;
    let f_true = 4.0;

    // Generate trace with dt = 0.01 up to t = 2.0
    for i in 0..=200 {
        let t = i as f64 * 0.01;
        // Approximation of damped oscillator y(t) = exp(-k/2 t) * cos(2*pi*f t)
        // For actual MCMC they will integrate it, but we generate the analytical approx for simplicity
        let y = (-k_true / 2.0 * t).exp() * (2.0 * PI * f_true * t).cos();
        writeln!(file, "{},{}", t, y).unwrap();
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
