#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uptime-monitor
    cd /home/user/uptime-monitor

    git init
    git config user.name "SRE Admin"
    git config user.email "sre@example.com"

    cargo init --bin

    # 1. Initial commit
    cat << 'EOF' > src/main.rs
use std::env;
use std::fs;

fn main() {
    println!("Uptime monitor starting...");
}
EOF
    git add .
    git commit -m "Initial commit"

    # 2. Add API key (the secret to be recovered)
    cat << 'EOF' > src/main.rs
use std::env;
use std::fs;

const API_KEY: &str = "sre-sec-99x1a2b3c";

fn main() {
    println!("Uptime monitor starting with hardcoded key...");
}
EOF
    git add src/main.rs
    git commit -m "Add legacy authentication logic"

    # 3. Remove API key (hide the secret)
    cat << 'EOF' > src/main.rs
use std::env;
use std::fs;
use serde::Deserialize;
use std::time::Duration;

#[derive(Deserialize, Debug)]
struct Endpoint {
    id: String,
    url: String,
    timeout: i32,
}

fn process_endpoints(file_path: &str) {
    let data = fs::read_to_string(file_path).expect("Unable to read file");
    let endpoints: Vec<Endpoint> = serde_json::from_str(&data).expect("JSON parsing failed");

    for ep in endpoints {
        // Data transformation: convert timeout to u64 duration
        // BUG: This will panic if timeout is negative
        let dur = Duration::from_secs(ep.timeout.try_into().unwrap());
        println!("Monitoring {} with timeout {:?}", ep.id, dur);
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() > 2 && args[1] == "process" {
        process_endpoints(&args[2]);
    } else {
        println!("Usage: cargo run -- process <file.json>");
    }
}
EOF
    echo 'serde = { version = "1.0", features = ["derive"] }' >> Cargo.toml
    echo 'serde_json = "1.0"' >> Cargo.toml

    git add src/main.rs Cargo.toml
    git commit -m "Refactor to use env vars and add endpoint processing"

    # Generate endpoints.json
    cat << 'EOF' > generate_endpoints.py
import json

endpoints = []
for i in range(1, 201):
    timeout = 30
    if i == 143:
        timeout = -15 # The bug trigger

    endpoints.append({
        "id": f"ep-{i:04d}",
        "url": f"https://service-{i}.example.com/health",
        "timeout": timeout
    })

with open("endpoints.json", "w") as f:
    json.dump(endpoints, f, indent=2)
EOF

    python3 generate_endpoints.py
    rm generate_endpoints.py

    git add endpoints.json
    git commit -m "Add sample endpoints list"

    chmod -R 777 /home/user
