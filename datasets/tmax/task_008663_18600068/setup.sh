#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc strace
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/log-tracer/src

    # Create the logs
    cat << 'EOF' > /home/user/logs/master.log
INFO Starting trace
ERROR Master failed to connect
[TRACE: service_a.log]
EOF

    cat << 'EOF' > /home/user/logs/service_a.log
INFO Service A init
ERROR Service A db timeout
ERROR Service A auth failure
[TRACE: service_b.log]
EOF

    cat << 'EOF' > /home/user/logs/service_b.log
INFO Service B doing work
ERROR Service B cache miss
[TRACE: service_a.log]
EOF

    # Create the Rust project
    cat << 'EOF' > /home/user/log-tracer/Cargo.toml
[package]
name = "log-tracer"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/log-tracer/src/main.rs
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub fn count_errors(start_file: &Path) -> usize {
    let mut to_visit = vec![start_file.to_path_buf()];
    let mut total_errors = 0;

    while let Some(current_file) = to_visit.pop() {
        let content = fs::read_to_string(&current_file).unwrap_or_default();
        let parent_dir = current_file.parent().unwrap_or(Path::new(""));

        for line in content.lines() {
            if line.contains("ERROR") {
                total_errors += 1;
            } else if line.starts_with("[TRACE: ") && line.ends_with("]") {
                let trace_file = &line[8..line.len() - 1];
                let next_path = parent_dir.join(trace_file);
                to_visit.push(next_path);
            }
        }
    }

    total_errors
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <log_file>", args[0]);
        std::process::exit(1);
    }
    let errors = count_errors(Path::new(&args[1]));
    println!("{}", errors);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
