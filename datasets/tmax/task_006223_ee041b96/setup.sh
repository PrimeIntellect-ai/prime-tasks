#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl git strace build-essential cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    /bin/bash -c '

    mkdir -p /home/user
    cd /home/user

    # Create input.log
    for i in {1..80}; do echo "INFO: Normal operation $i" >> input.log; done
    for i in {1..20}; do echo "CRITICAL: System failure $i" >> input.log; done

    # Create Rust project
    cargo new log_processor
    cd log_processor

    # Base code (Good)
    cat << "EOF" > src/main.rs
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <logfile>", args[0]);
        std::process::exit(1);
    }

    let contents = fs::read_to_string(&args[1]).unwrap();
    let mut count = 0;

    for _line in contents.lines() {
        count += 1;
    }

    println!("Total entries: {}", count);
}
EOF

    git init -b main
    git config user.name "DevOps"
    git config user.email "devops@example.com"
    git add .
    git commit -m "Initial commit"
    git tag v1.0.0

    # Add some dummy commits
    for i in {1..3}; do
        echo "// Dummy comment $i" >> src/main.rs
        git add .
        git commit -m "Refactor: Update comments $i"
    done

    # Introduce the bug (Bad Commit)
    cat << "EOF" > src/main.rs
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <logfile>", args[0]);
        std::process::exit(1);
    }

    let contents = fs::read_to_string(&args[1]).unwrap();
    let mut count = 0;

    let has_override = fs::metadata("/etc/log_processor/features.conf").is_ok();

    for line in contents.lines() {
        if line.contains("CRITICAL") && !has_override {
            // Silently skip if override config is missing
            continue;
        }
        count += 1;
    }

    println!("Total entries: {}", count);
}
EOF
    git add .
    git commit -m "Feature: Add override config support for critical logs"
    BAD_COMMIT=$(git rev-parse HEAD)

    # Add more dummy commits
    for i in {4..6}; do
        echo "// Another dummy comment $i" >> src/main.rs
        git add .
        git commit -m "Docs: Update docs $i"
    done

    echo "{\"bad_commit\":\"$BAD_COMMIT\",\"missing_file\":\"/etc/log_processor/features.conf\"}" > /tmp/expected_report.json
    '

    chmod -R 777 /home/user
