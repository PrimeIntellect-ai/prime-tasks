#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app
    ffmpeg -f lavfi -i "color=c=red:s=100x100:d=1" \
           -f lavfi -i "color=c=green:s=100x100:d=1" \
           -f lavfi -i "color=c=blue:s=100x100:d=1" \
           -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1:a=0[outv]" \
           -map "[outv]" -r 1 /app/sequence.mp4

    cat << 'EOF' > /app/legacy_validator.rs
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    let input = fs::read_to_string(&args[1]).unwrap();

    // BUG: borrow checker error introduced intentionally
    let mut current_path = String::new();

    for line in input.lines() {
        let segments: Vec<&str> = line.split('/').collect();
        let mut valid = true;
        let mut last_state = "";

        for seg in &segments {
            current_path = seg.to_string(); // borrow checker issue simulated
            let s = current_path.as_str();
            if s == "red" || s == "green" || s == "blue" {
                if last_state != "" {
                    // LEGACY CYCLE: blue -> green -> red
                    if last_state == "blue" && s != "green" { valid = false; }
                    if last_state == "green" && s != "red" { valid = false; }
                    if last_state == "red" && s != "blue" { valid = false; }
                }
                last_state = s;
            }
        }
        if valid {
            println!("{}", line);
        }
    }
}
EOF

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/corpus/clean/valid1.txt
/api/v1/route/red/green
/red/green/blue/red
/home/user/green/api/blue/red/green
/blue/red
/green
EOF

    cat << 'EOF' > /app/corpus/evil/invalid1.txt
/api/v1/route/red/blue
/red/green/green
/blue/green/red
/home/user/red/green/blue/green
/blue/blue
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
