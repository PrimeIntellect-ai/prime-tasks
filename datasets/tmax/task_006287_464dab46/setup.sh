#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest jupyter pandas nbconvert

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data_gen/src

    cat << 'EOF' > /home/user/data_gen/Cargo.toml
[package]
name = "data_gen"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/data_gen/src/solver.rs
pub fn solve_vdp(mut y1: f64, mut y2: f64, t_end: f64, tol: f64) -> (f64, f64) {
    let mut t = 0.0;
    let mut dt = 0.01;
    let mu = 1.0;

    while t < t_end {
        if t + dt > t_end {
            dt = t_end - t;
        }

        let y1_e = y1 + dt * y2;
        let y2_e = y2 + dt * (mu * (1.0 - y1*y1) * y2 - y1);

        let f2_start = mu * (1.0 - y1*y1) * y2 - y1;
        let f2_end = mu * (1.0 - y1_e*y1_e) * y2_e - y1_e;

        let y1_h = y1 + (dt / 2.0) * (y2 + (y2 + dt * f2_start));
        let y2_h = y2 + (dt / 2.0) * (f2_start + f2_end);

        let error = ((y1_e - y1_h).powi(2) + (y2_e - y2_h).powi(2)).sqrt().max(1e-10);

        if error < tol {
            y1 = y1_h;
            y2 = y2_h;
            t += dt;
        }

        // BUG: Incorrect step size adaptation
        dt = dt * (error / tol).powf(0.5); 
        dt = dt.clamp(1e-5, 0.1);
    }
    (y1, y2)
}
EOF

    cat << 'EOF' > /home/user/data_gen/src/main.rs
mod solver;

fn main() {
    // Implement Monte Carlo loop and CSV output here
}
EOF

    chown -R user:user /home/user/data_gen
    chmod -R 777 /home/user
