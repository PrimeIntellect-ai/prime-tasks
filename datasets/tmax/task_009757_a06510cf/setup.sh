#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/spectro_solve/src

    cat << 'EOF' > /home/user/spectro_solve/Cargo.toml
[package]
name = "spectro_solve"
version = "0.1.0"
edition = "2021"
EOF

    cat << 'EOF' > /home/user/spectro_solve/src/lib.rs
pub fn solve_concentrations(a1: f64, b1: f64, m1: f64, a2: f64, b2: f64, m2: f64) -> (f64, f64) {
    // Solves the system:
    // a1*x + b1*y = m1
    // a2*x + b2*y = m2
    let det = a1 * b2 - b1 * a2;

    // BUG: Incorrect sign in determinant calculation for Cramer's rule
    let det_x = m1 * b2 + b1 * m2; 
    let det_y = a1 * m2 - m1 * a2;

    (det_x / det, det_y / det)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_reference_dataset() {
        // Known reference: mix of 2.0 A and 1.0 B
        // Wavelength 1: A=2.0, B=1.0, Mix=5.0
        // Wavelength 2: A=1.0, B=3.0, Mix=5.0
        let (c_a, c_b) = solve_concentrations(2.0, 1.0, 5.0, 1.0, 3.0, 5.0);
        assert!((c_a - 2.0).abs() < 1e-6, "Expected c_a = 2.0, got {}", c_a);
        assert!((c_b - 1.0).abs() < 1e-6, "Expected c_b = 1.0, got {}", c_b);
    }
}
EOF

    cat << 'EOF' > /home/user/spectro_solve/src/main.rs
use spectro_solve::solve_concentrations;

fn main() {
    // Wavelength 1: A=0.8, B=0.3, Mix=2.5
    // Wavelength 2: A=0.2, B=0.9, Mix=2.95
    let (c_a, c_b) = solve_concentrations(0.8, 0.3, 2.5, 0.2, 0.9, 2.95);
    println!("Component A: {:.2}", c_a);
    println!("Component B: {:.2}", c_b);
}
EOF

    chmod -R 777 /home/user
