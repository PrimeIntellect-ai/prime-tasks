#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sim_solver
    cd /home/user/sim_solver
    cargo init --bin

    mkdir -p /home/user/sim_solver/.cargo
    cat << 'EOF' > /home/user/sim_solver/.cargo/config.toml
[build]
rustflags = ["-C", "link-arg=-lnonexistent_legacy_math_lib"]
EOF

    cat << 'EOF' > /home/user/sim_solver/src/main.rs
fn main() {
    // Customer's initial guess that causes oscillation between 0 and 1
    let mut x: f64 = 0.0; 
    let max_iter = 1000;
    let tol = 1e-6;

    for _ in 0..max_iter {
        let fx = x.powi(3) - 2.0 * x + 2.0;
        let dfx = 3.0 * x.powi(2) - 2.0;

        let x_new = x - fx / dfx;

        if (x_new - x).abs() < tol {
            println!("Converged root: {:.6}", x_new);
            return;
        }
        x = x_new;
    }

    println!("Failed to converge");
}
EOF

    chmod -R 777 /home/user
