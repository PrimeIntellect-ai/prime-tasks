#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr golang-go cargo imagemagick fonts-dejavu-core
    pip3 install pytest

    # Create the image
    mkdir -p /app
    convert -size 800x300 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
      -draw "text 20,50 'CONFIDENTIAL SYSTEM SPECIFICATION'" \
      -draw "text 20,120 'API_TOKEN: Sigma77Omega'" \
      -draw "text 20,190 'MATH_MAGIC_CONSTANT: 2.7182818'" \
      /app/system_spec.png

    # Create the Rust project
    mkdir -p /home/user/math_engine/src
    cat << 'EOF' > /home/user/math_engine/Cargo.toml
[package]
name = "math_engine"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/math_engine/src/main.rs
mod constants;
use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Missing argument");
        std::process::exit(1);
    }
    let n: f64 = args[1].parse().expect("Invalid number");
    println!("{}", n * constants::MATH_MAGIC_CONSTANT);
}
EOF

    cat << 'EOF' > /home/user/math_engine/src/constants.rs
// TODO: Define MATH_MAGIC_CONSTANT here based on the spec
EOF

    # Create go_server directory
    mkdir -p /home/user/go_server

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
