#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo tesseract-ocr imagemagick
    pip3 install pytest requests

    mkdir -p /app/calculator/src
    cat << 'EOF' > /app/calculator/Cargo.toml
[package]
name = "calculator"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /app/calculator/src/main.rs
use std::env;

// Missing constant goes here

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 2 {
        eprintln!("Usage: calculator <number>");
        std::process::exit(1);
    }
    let num: i64 = args[1].parse().unwrap();
    println!("{}", num * CONSTANT);
}
EOF

    # Create the blueprint image
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 48 -fill black -draw "text 20,60 'CONSTANT=105'" /app/blueprint.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
