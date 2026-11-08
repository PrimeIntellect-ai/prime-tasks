#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install rust, ffmpeg, and build dependencies
    apt-get install -y cargo rustc ffmpeg build-essential pkg-config libssl-dev curl

    # Create directories
    mkdir -p /home/user/video_analyzer/src
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create dummy video with exactly 150 frames
    ffmpeg -y -f lavfi -i color=c=black:s=320x240:r=30 -frames:v 150 -c:v libx264 -preset ultrafast /app/video_fixture.mp4

    # Create Rust project
    cat << 'EOF' > /home/user/video_analyzer/Cargo.toml
[package]
name = "video_analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/video_analyzer/src/main.rs
use serde::{Deserialize, Serialize};
use std::env;
use std::fs;

#[derive(Serialize, Deserialize, Debug)]
struct Payload {
    frame_index: usize,
    motion_vectors: Vec<f64>,
}

fn refine_motion(vectors: &[f64]) -> bool {
    let mut i = 0;
    while i < vectors.len() {
        if vectors[i] < 0.0 {
            // Bug: infinite loop if vector is negative
        } else {
            i += 1;
        }
    }
    true
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        std::process::exit(1);
    }
    let data = fs::read_to_string(&args[1]).unwrap();
    let payload: Payload = serde_json::from_str(&data).unwrap();

    // Bug: out of bounds array access
    let dummy_frames = vec![0; 100];
    let _val = dummy_frames[payload.frame_index];

    refine_motion(&payload.motion_vectors);
}
EOF

    # Create corpora
    cat << 'EOF' > /app/corpora/clean/payload_1.json
{"frame_index": 10, "motion_vectors": [1.0, 2.0]}
EOF

    cat << 'EOF' > /app/corpora/evil/payload_1.json
{"frame_index": 10, "motion_vectors": [-1.0, 2.0]}
EOF

    cat << 'EOF' > /app/corpora/evil/payload_2.json
{"frame_index": 160, "motion_vectors": [1.0, 2.0]}
EOF

    cat << 'EOF' > /app/corpora/evil/payload_3.json
{"frame_index": 10, "motion_vectors": [-1.0, 2.0]
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
