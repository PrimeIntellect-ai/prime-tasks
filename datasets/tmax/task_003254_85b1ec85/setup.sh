#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        rustc \
        cargo \
        sqlite3 \
        ffmpeg \
        protobuf-compiler \
        libprotobuf-dev

    pip3 install pytest

    mkdir -p /app
    # Generate a dummy 1-second video with 10 frames
    ffmpeg -f lavfi -i testsrc=duration=1:size=320x240:rate=10 -c:v libx264 /app/incident.mp4

    useradd -m -s /bin/bash user || true

    # Setup rust project
    cd /home/user
    cargo new video_service
    cd video_service

    cat << 'EOF' > Cargo.toml
[package]
name = "video_service"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.0", features = ["full"] }
warp = "0.3"
prost = "0.11"
# tonic is missing

[build-dependencies]
tonic-build = "0.8"
EOF

    mkdir -p proto
    cat << 'EOF' > proto/video.proto
syntax = "proto3";
package video;

service VideoService {
    rpc GetFrameCount (Empty) returns (FrameCountResponse);
}

message Empty {}

message FrameCountResponse {
    uint32 count = 1;
}
EOF

    cat << 'EOF' > build.rs
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::compile_protos("proto/video.proto")?;
    Ok(())
}
EOF

    cat << 'EOF' > src/processor.rs
pub fn process() {
    loop {}
}
EOF

    cat << 'EOF' > src/main.rs
mod processor;

fn main() {
    processor::process();
}
EOF

    mkdir -p data
    sqlite3 data/metrics.db "CREATE TABLE video_stats (id INTEGER PRIMARY KEY, name TEXT);"
    sqlite3 data/metrics.db "INSERT INTO video_stats (name) VALUES ('test');"
    # Corrupt the SQLite database header
    dd if=/dev/urandom of=data/metrics.db bs=100 count=1 conv=notrunc

    chmod -R 777 /home/user
