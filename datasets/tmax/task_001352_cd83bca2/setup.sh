#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    rustc \
    cargo \
    ffmpeg \
    sqlite3
pip3 install pytest

mkdir -p /app/rust_counter/src
cat << 'EOF' > /app/rust_counter/Cargo.toml
[package]
name = "rust_counter"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /app/rust_counter/src/main.rs
fn main() {
    let mut s = String::from("hello world");
    let word1 = get_first_word(&s);
    s.clear(); // Error: cannot borrow `s` as mutable because it is also borrowed as immutable
    println!("The first word is: {}", word1);
}
fn get_first_word(s: &String) -> &str {
    &s[..5]
}
EOF

sqlite3 /app/video_stats.db "CREATE TABLE stats (video_name TEXT, frames INTEGER);"
sqlite3 /app/video_stats.db "INSERT INTO stats (video_name, frames) VALUES ('traffic.mp4', 100);"

# Create a dummy video file
ffmpeg -f lavfi -i testsrc=duration=2:size=320x240:rate=30 /app/traffic.mp4

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
