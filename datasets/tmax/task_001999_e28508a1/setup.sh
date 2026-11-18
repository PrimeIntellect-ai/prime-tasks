#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-opencv python3-numpy cargo
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/gen_video.py
import cv2
import numpy as np
import os

os.makedirs('/app', exist_ok=True)
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter('/app/experiment.mp4', fourcc, 30.0, (640, 480))

# Ground truth parameters
A, B, C = 0.002, -1.2, 200.0

for x in range(50, 550, 10):
    img = np.ones((480, 640, 3), dtype=np.uint8) * 255
    y = int(A * (x**2) + B * x + C)
    if 0 <= y < 480:
        cv2.circle(img, (x, y), 5, (0, 0, 0), -1)
    out.write(img)
out.release()
EOF

python3 /tmp/gen_video.py

useradd -m -s /bin/bash user || true

mkdir -p /home/user/sim_engine/src

cat << 'EOF' > /home/user/sim_engine/Cargo.toml
[package]
name = "sim_engine"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /home/user/sim_engine/src/main.rs
mod trajectory_constants;
fn main() {
    println!("Engine initialized with A={}", trajectory_constants::COEFF_A);
}
EOF

cat << 'EOF' > /home/user/sim_engine/src/lib.rs
pub mod trajectory_constants;

#[cfg(test)]
mod tests {
    use super::trajectory_constants::*;
    #[test]
    fn test_coefficients_bounds() {
        assert!(COEFF_A > 0.001 && COEFF_A < 0.005);
    }
}
EOF

chmod -R 777 /home/user
chmod -R 777 /app
