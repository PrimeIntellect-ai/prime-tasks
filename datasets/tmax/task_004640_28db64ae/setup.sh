#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg tesseract-ocr cargo fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app
    # Generate the video with the required text
    ffmpeg -f lavfi -i color=c=black:s=1280x720:d=2 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='cargo run -- --key /home/admin/.ssh/id_rsa --passphrase \"Omega\$hield2024\" --target 10.0.0.5':fontcolor=white:fontsize=24:x=50:y=50" -c:v libx264 -t 2 -pix_fmt yuv420p /app/admin_session.mp4

    # Create the Rust project
    mkdir -p /home/user/rusty_scanner/src
    cat << 'EOF' > /home/user/rusty_scanner/Cargo.toml
[package]
name = "rusty_scanner"
version = "0.1.0"
edition = "2021"

[dependencies]
clap = { version = "4.0", features = ["derive"] }
EOF

    cat << 'EOF' > /home/user/rusty_scanner/src/main.rs
use clap::Parser;
use std::process::Command;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    #[arg(short, long)]
    key: String,

    #[arg(short, long)]
    passphrase: String,

    #[arg(short, long)]
    target: String,
}

fn main() {
    let args = Args::parse();
    let mut child = Command::new("sh")
        .arg("-c")
        .arg(format!("echo 'Connecting to {} with key {}'; sleep 1", args.target, args.key))
        .arg(&args.passphrase) // Vulnerable: passing passphrase as argument
        .spawn()
        .expect("Failed to execute child");
    child.wait().expect("Child process wasn't running");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
