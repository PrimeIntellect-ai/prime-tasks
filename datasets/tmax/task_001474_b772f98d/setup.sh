#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest numpy

    mkdir -p /home/user/ml_prep/src
    cd /home/user/ml_prep

    cat << 'EOF' > Cargo.toml
[package]
name = "ml_prep"
version = "0.1.0"
edition = "2021"

[dependencies]
nalgebra = "0.32"
csv = "1.3"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > src/main.rs
fn main() {
    println!("Hello, world!");
}
EOF

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
np.random.seed(42)

# Generate features
cov = np.array([[1.0, 0.5, 0.2], [0.5, 1.0, 0.3], [0.2, 0.3, 1.0]])
L_true = np.linalg.cholesky(cov)
X = np.random.randn(100, 3) @ L_true.T + np.array([1.0, 2.0, 3.0])

# Generate target
true_beta = np.array([1.5, -2.0, 0.5])
y = X @ true_beta + np.random.randn(100) * 0.1

# Save to csv
data = np.hstack((X, y.reshape(-1, 1)))
np.savetxt('/home/user/ml_prep/data.csv', data, delimiter=',', fmt='%.6f')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
