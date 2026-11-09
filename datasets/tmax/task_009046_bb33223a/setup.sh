#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/seq_model/src

    cat << 'EOF' > /home/user/seq_model/Cargo.toml
[package]
name = "seq_model"
version = "0.1.0"
edition = "2021"

[dependencies]
nalgebra = "0.32"
EOF

    cat << 'EOF' > /home/user/seq_model/src/main.rs
use nalgebra::{Vector3, Matrix3};

fn main() {
    let a = Matrix3::new(
        -0.5, 0.1, 0.0,
         0.2, -0.3, 0.1,
         0.0, 0.2, -0.4
    );

    let mut state = Vector3::new(100.0, 50.0, 25.0);
    let mut t = 0.0;
    let t_end = 5.0;
    let mut dt = 0.1;
    let tol = 1e-3;

    while t < t_end {
        if t + dt > t_end {
            dt = t_end - t;
        }

        // Heun's method (predictor-corrector) for error estimation
        let k1 = a * state;
        let predictor = state + k1 * dt;
        let k2 = a * predictor;
        let corrector = state + (k1 + k2) * (dt / 2.0);

        // Error is the difference between predictor (Euler) and corrector (Heun)
        let error = (corrector - predictor).norm();

        if error > tol {
            // BUG: Inverted logic here
            dt *= 1.2; 
        } else {
            state = corrector;
            t += dt;
            // BUG: Inverted logic here
            dt *= 0.5;
        }
    }

    println!("{:.5},{:.5},{:.5}", state[0], state[1], state[2]);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
