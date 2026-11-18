#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        curl \
        ffmpeg \
        build-essential

    pip3 install pytest opencv-python-headless numpy requests

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    export PATH="$HOME/.cargo/bin:$PATH"

    # Create video fixture
    mkdir -p /app
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 -c:v libx264 /app/video.mp4

    # Create project structure
    mkdir -p /home/user/project/rust_ext/src

    # Create messy_app.py
    cat << 'EOF' > /home/user/project/messy_app.py
import cv2
import json

def process():
    cap = cv2.VideoCapture('/app/video.mp4')
    brightness = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        # Slow pure python brightness
        total = 0
        count = 0
        for row in frame:
            for pixel in row:
                total += sum(pixel)
                count += 3
        brightness.append(total / count)
    print(json.dumps({"video": "/app/video.mp4", "frames_brightness": brightness}))

if __name__ == "__main__":
    process()
EOF

    # Create Cargo.toml
    cat << 'EOF' > /home/user/project/rust_ext/Cargo.toml
[package]
name = "fast_video_utils"
version = "0.1.0"
edition = "2021"

[lib]
name = "fast_video_utils"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

    # Create lib.rs
    cat << 'EOF' > /home/user/project/rust_ext/src/lib.rs
use pyo3::prelude::*;

#[pyfunction]
fn calculate_brightness(frame_data: Vec<u8>) -> PyResult<f64> {
    // Intentional borrow checker / ownership error:
    let data_ref = &frame_data;
    let mut sum: f64 = 0.0;
    for val in frame_data { // consumes frame_data while data_ref holds a borrow
        sum += val as f64;
    }
    // agent must fix this to just iterate correctly.
    Ok(sum / (data_ref.len() as f64)) 
}

#[pymodule]
fn fast_video_utils(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(calculate_brightness, m)?)?;
    Ok(())
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
