#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/state-sync/src

    cat << 'EOF' > /home/user/logs/service_a.log
2023-10-27T10:00:01Z service_a "/var/data/file1.txt" OK
2023-10-27T10:00:03Z service_a "/var/data/file2.txt" OK
2023-10-27T10:00:05Z service_a "/var/data/critical data.txt" OK
EOF

    cat << 'EOF' > /home/user/logs/service_b.log
2023-10-27T10:00:02Z service_b "/var/data/config.json" OK
2023-10-27T10:00:04Z service_b "/var/data/logs.tar.gz" OK
EOF

    cat << 'EOF' > /home/user/logs/state-sync.log
2023-10-27T10:00:01Z state-sync "SYNC_START" PENDING
2023-10-27T10:00:06Z state-sync "SYNC_RETRY" FAILED
2023-10-27T10:00:11Z state-sync "SYNC_RETRY" FAILED
EOF

    cat << 'EOF' > /home/user/logs/state.txt
2023-10-27T10:00:01Z service_a "/var/data/file1.txt" OK
2023-10-27T10:00:02Z service_b "/var/data/config.json" OK
2023-10-27T10:00:03Z service_a "/var/data/file2.txt" OK
2023-10-27T10:00:04Z service_b "/var/data/logs.tar.gz" OK
2023-10-27T10:00:05Z service_a "/var/data/critical data.txt" OK
EOF

    cat << 'EOF' > /home/user/state-sync/Cargo.toml
[package]
name = "state-sync"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/state-sync/src/main.rs
use std::env;
use std::fs::File;
use std::io::{self, BufRead};
use std::process;

fn parse_log_line(line: &str) -> Option<(String, String, String, String)> {
    // BUGGY PARSER: Naive split by whitespace
    let parts: Vec<&str> = line.split_whitespace().collect();
    if parts.len() == 4 {
        let ts = parts[0].to_string();
        let svc = parts[1].to_string();
        let path = parts[2].trim_matches('"').to_string();
        let status = parts[3].to_string();
        Some((ts, svc, path, status))
    } else {
        None
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: state-sync <state_file>");
        process::exit(1);
    }

    let file = File::open(&args[1]).unwrap();
    let reader = io::BufReader::new(file);

    let mut success = true;

    for line in reader.lines() {
        if let Ok(l) = line {
            match parse_log_line(&l) {
                Some((_, _, path, _)) => {
                    println!("Synced: {}", path);
                }
                None => {
                    eprintln!("Parse error on line: {}. Triggering convergence retry...", l);
                    success = false;
                }
            }
        }
    }

    if success {
        println!("Convergence achieved.");
        process::exit(0);
    } else {
        println!("Infinite loop simulated. Exiting with failure.");
        process::exit(1);
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
