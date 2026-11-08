#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git cargo rustc
    pip3 install pytest

    mkdir -p /home/user/service_repo
    cd /home/user/service_repo
    git init
    cargo init

    cat << 'EOF' > src/main.rs
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: processor <log_file>");
        std::process::exit(1);
    }

    let content = fs::read_to_string(&args[1]).expect("Failed to read file");
    let mut buffer = Vec::new();
    let mut processed_count = 0;

    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() { continue; }

        if line.starts_with("REQ") {
            buffer.push(line);
        } else if line == "PROCESS_WINDOW" {
            let mut i = 0;
            // Bug: off-by-one in slice boundary
            while i <= buffer.len() {
                let chunk_end = i + 3;
                if chunk_end > buffer.len() {
                    break;
                }
                // Off-by-one: using ..= instead of ..
                let _chunk = &buffer[i..=chunk_end]; 
                processed_count += 3;
                i += 3;
            }
            buffer.clear();
        }
    }
    println!("Processed: {}", processed_count);
}
EOF

    git add src/main.rs Cargo.toml
    git config user.name "Admin"
    git config user.email "admin@example.com"
    git commit -m "Initial commit"

    cat << 'EOF' > crashed_requests.log
REQ A
REQ B
PROCESS_WINDOW
REQ C
REQ D
REQ E
PROCESS_WINDOW
REQ F
REQ G
REQ H
REQ I
PROCESS_WINDOW
EOF

    git add crashed_requests.log
    git commit -m "Add crash logs"
    git reset --hard HEAD~1

    # Expire the reflog so the commit becomes unreachable and fsck can find it
    git reflog expire --expire=now --all

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
