#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc binutils
    pip3 install pytest

    mkdir -p /app/bin
    mkdir -p /app/sample_logs
    mkdir -p /verify/corpus/clean
    mkdir -p /verify/corpus/evil

    cat << 'EOF' > /tmp/log_aggregator.rs
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { return; }
    let contents = fs::read_to_string(&args[1]).unwrap();
    for line in contents.lines() {
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() >= 2 && parts[1] == "FATAL" {
            if parts.len() < 3 || parts[2].is_empty() {
                // Trigger the panic
                let crash: Option<String> = None;
                crash.unwrap();
            }
        }
    }
}
EOF

    rustc /tmp/log_aggregator.rs -o /app/bin/log_aggregator
    strip -s /app/bin/log_aggregator
    rm /tmp/log_aggregator.rs

    cat << 'EOF' > /app/sample_logs/clean.csv
2023-10-10 10:00:00,INFO,All good
2023-10-10 10:01:00,WARN,Low memory
2023-10-10 10:02:00,FATAL,Database connection lost
EOF

    cat << 'EOF' > /app/sample_logs/crash.csv
2023-10-10 10:00:00,INFO,All good
2023-10-10 10:01:00,FATAL,
2023-10-10 10:02:00,INFO,Restarting
EOF

    cat << 'EOF' > /verify/corpus/clean/file1.csv
2023-10-10 10:00:00,INFO,All good
2023-10-10 10:01:00,FATAL,System crash
EOF

    cat << 'EOF' > /verify/corpus/clean/file2.csv
2023-10-10 10:00:00,INFO,All good
2023-10-10 10:01:00,ERROR,
EOF

    cat << 'EOF' > /verify/corpus/evil/file1.csv
2023-10-10 10:00:00,INFO,All good
2023-10-10 10:01:00,FATAL,
EOF

    cat << 'EOF' > /verify/corpus/evil/file2.csv
FATAL,
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
