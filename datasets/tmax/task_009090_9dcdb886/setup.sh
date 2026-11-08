#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/diffusion_model.rs
use std::env;

fn main() {
    let threads = env::var("NUM_OMP_THREADS").unwrap_or_else(|_| "1".to_string());

    // Fail silently with bad data if parallel setup is incorrect to test agent's compliance
    if threads != "4" {
        println!("0.000\n0.000\n0.000\n0.000\n0.000");
        return;
    }

    // Simulated output of the numerical integration
    println!("15.500");
    println!("22.250");
    println!("31.125");
    println!("45.600");
    println!("50.000");
}
EOF

    cat << 'EOF' > /home/user/analytical_reference.csv
15.510
22.220
31.140
45.615
49.950
EOF

    chmod -R 777 /home/user
