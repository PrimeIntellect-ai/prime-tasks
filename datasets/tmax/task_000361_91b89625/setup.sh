#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo pkg-config libfreetype6-dev libfontconfig1-dev
    pip3 install pytest

    mkdir -p /home/user/oscillator_fit/src
    cd /home/user/oscillator_fit

    cat << 'EOF' > Cargo.toml
[package]
name = "oscillator_fit"
version = "0.1.0"
edition = "2021"

[dependencies]
rand = "0.8"
plotters = "0.3"
EOF

    cat << 'EOF' > src/integrator.rs
pub struct AdaptiveEuler {
    pub tolerance: f64,
}

impl AdaptiveEuler {
    pub fn step(&self, dt: &mut f64, error: f64) {
        // BUG: Inverted step-size adaptation
        if error > self.tolerance {
            *dt *= 2.0; // Should be 0.5
        } else if error < self.tolerance * 0.1 {
            *dt *= 0.5; // Should be 2.0
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_adaptation() {
        let solver = AdaptiveEuler { tolerance: 0.01 };
        let mut dt = 0.1;
        solver.step(&mut dt, 0.05); // High error
        assert!(dt < 0.1, "Step size should decrease on high error");
    }
}
EOF

    cat << 'EOF' > src/mcmc.rs
use rand::Rng;

pub fn mh_accept(current_log_lik: f64, proposed_log_lik: f64) -> bool {
    let mut rng = rand::thread_rng();
    // TODO: Implement Metropolis-Hastings acceptance criterion
    // Hint: let acceptance_prob = (proposed_log_lik - current_log_lik).exp().min(1.0);
    // Return true if accepted, false otherwise
    false
}
EOF

    cat << 'EOF' > src/main.rs
mod integrator;
mod mcmc;

use std::fs::File;
use std::io::Write;
use plotters::prelude::*;

fn main() {
    // Mock MCMC loop and plotting for the sake of the exercise
    let mut c = 0.5;
    let mut k = 2.0;

    // Simulate finding the fit
    if mcmc::mh_accept(-10.0, -2.0) {
        c = 0.51;
        k = 1.98;
    }

    println!("c: {:.2}, k: {:.2}", c, k);

    // Create dummy plot
    let root = BitMapBackend::new("/home/user/fit.png", (640, 480)).into_drawing_area();
    root.fill(&WHITE).unwrap();
    let mut chart = ChartBuilder::on(&root)
        .build_cartesian_2d(0f32..10f32, -1f32..1f32)
        .unwrap();
    chart.configure_mesh().draw().unwrap();
}
EOF

    cat << 'EOF' > data.csv
0.0, 1.0
0.1, 0.9
0.2, 0.7
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
