#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create user
    useradd -m -s /bin/bash user || true

    # Create data directory and CSV
    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/sensors.csv
id,temperature,humidity,status
1,20.0,50.0, OK
2,22.0,55.0,OK
3,21.0,52.0,ERROR
4,25.0,60.0, OK 
5,19.0,48.0,OK
6,18.0,45.0, FAIL
EOF

    # Create Rust project
    mkdir -p /home/user/sensor_etl/src

    cat << 'EOF' > /home/user/sensor_etl/Cargo.toml
[package]
name = "sensor_etl"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.1"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/sensor_etl/src/main.rs
use std::error::Error;
use std::fs::File;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Record {
    id: i32,
    temperature: f64,
    humidity: f64,
    status: String,
}

fn main() -> Result<(), Box<dyn Error>> {
    let mut rdr = csv::Reader::from_path("/home/user/data/sensors.csv")?;
    let mut processed_rows = 0;

    for result in rdr.deserialize() {
        let record: Record = result?;
        // BUG: Fails to account for whitespace in CSV
        if record.status == "OK" {
            processed_rows += 1;
        }
    }

    println!("Processed rows: {}", processed_rows);
    Ok(())
}
EOF

    # Make rust available for the user
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | su - user -c "sh -s -- -y"

    chmod -R 777 /home/user
