#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc time
    pip3 install pytest

    mkdir -p /home/user/shift_processor/src
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/shift_processor/Cargo.toml
[package]
name = "shift_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/shift_processor/src/main.rs
mod processor;
use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <file>", args[0]);
        std::process::exit(1);
    }

    // Mock reading for the exercise
    let mock_data = vec![
        String::from("A,10,20"),
        String::from("B,15,25"),
        String::from("C,20,30"),
    ];

    let valid = processor::process_shifts(&mock_data);
    println!("{}", valid.len());
}
EOF

    cat << 'EOF' > /home/user/shift_processor/src/processor.rs
#[derive(Debug)]
pub struct Shift {
    pub id: String,
    pub start: i32,
    pub end: i32,
}

pub fn process_shifts(data: &Vec<String>) -> Vec<&String> {
    let mut valid_records = Vec::new();
    let mut last_end = 0;

    for record in data {
        let parts: Vec<&str> = record.split(',').collect();
        if parts.len() == 3 {
            let start: i32 = parts[1].parse().unwrap();
            let end: i32 = parts[2].parse().unwrap();

            if start >= last_end {
                last_end = end;
                // Intentional borrow checker error: returning reference to local variable or pushing reference from data.
                // Since data is &Vec<String>, we can push &String, but let's make it fail.
                valid_records.push(record);
            }
        }
    }

    valid_records
}
EOF

    cat << 'EOF' > /home/user/data/input.csv
A,10,20
B,15,25
C,20,30
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
