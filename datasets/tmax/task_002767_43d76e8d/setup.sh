#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /app/log-processor/src
    cat << 'EOF' > /app/log-processor/Cargo.toml
[package]
name = "log-processor"
version = "1.0.0"
edition = "2021"

[dependencies]
csv = "1.3.0"
serde = { version = "1.0", features = ["derive"] }
EOF

    cat << 'EOF' > /app/log-processor/src/main.rs
use std::io::{self, BufRead};

fn main() {
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let l = line.unwrap();
        let mut rdr = csv::ReaderBuilder::new().from_reader(l.as_bytes());
        for result in rdr.records() {
            let _record = result.unwrap();
        }
    }
}
EOF

    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/log_processor_oracle
#!/bin/bash
# Dummy oracle for initial state tests
EOF
    chmod +x /opt/oracle/log_processor_oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
