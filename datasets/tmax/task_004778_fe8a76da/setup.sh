#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo curl
pip3 install pytest

mkdir -p /home/user/log-parser/src
mkdir -p /home/user/logs

LOG_FILE="/home/user/logs/server.log"
rm -f $LOG_FILE

# Use seq to ensure compatibility across shells
for i in $(seq 1 7341); do
    echo "2023-10-12T10:00:00Z 192.168.1.10 200 SUCCESS_LOG_ENTRY_$(printf "%04d" $i)" >> $LOG_FILE
done

# Inject the malformed line at line 7342
echo "2023-10-12T14:32:01Z 10.0.0.42" >> $LOG_FILE

# Finish the log file
for i in $(seq 7343 10000); do
    echo "2023-10-12T10:00:00Z 192.168.1.10 200 SUCCESS_LOG_ENTRY_$(printf "%04d" $i)" >> $LOG_FILE
done

# Create Cargo.toml
cat << 'EOF' > /home/user/log-parser/Cargo.toml
[package]
name = "log-parser"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

# Create buggy main.rs
cat << 'EOF' > /home/user/log-parser/src/main.rs
use std::env;
use std::fs::File;
use std::io::{self, BufRead};

#[derive(Debug, PartialEq)]
struct LogEntry {
    timestamp: String,
    ip: String,
    status: u16,
    message: String,
}

fn parse_line(line: &str) -> Option<LogEntry> {
    let parts: Vec<&str> = line.split(' ').collect();

    // BUG: Assumes at least 4 parts exist without checking
    let timestamp = parts[0].to_string();
    let ip = parts[1].to_string();
    let status = parts[2].parse::<u16>().unwrap();
    let message = parts[3].to_string();

    Some(LogEntry {
        timestamp,
        ip,
        status,
        message,
    })
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <log_file>", args[0]);
        std::process::exit(1);
    }

    let file = File::open(&args[1]).expect("Failed to open file");
    let reader = io::BufReader::new(file);

    let mut valid_count = 0;

    for line_result in reader.lines() {
        let line = line_result.expect("Failed to read line");
        if let Some(_) = parse_line(&line) {
            valid_count += 1;
        }
    }

    println!("Successfully parsed {} lines.", valid_count);
}
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/log-parser /home/user/logs
chmod -R 777 /home/user
