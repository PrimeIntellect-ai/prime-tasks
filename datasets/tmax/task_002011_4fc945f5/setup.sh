#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential ca-certificates
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    export RUSTUP_HOME=/home/user/.rustup
    export CARGO_HOME=/home/user/.cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

    mkdir -p /home/user/data_prep/src

    cat << 'EOF' > /home/user/raw_data.csv
id,category,clicks,response_time
1,A,10,100.5
2,B,,200.0
3,A,15,150.2
4,C,20,120.0
5,B,,180.5
6,A,5,90.0
7,C,,210.0
8,B,12,130.5
9,A,8,110.0
10,C,25,105.0
EOF

    cat << 'EOF' > /home/user/data_prep/Cargo.toml
[package]
name = "data_prep"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.1"
serde = { version = "1.0", features = ["derive"] }
EOF

    cat << 'EOF' > /home/user/data_prep/src/main.rs
use csv::{Reader, Writer};
use serde::{Deserialize, Serialize};
use std::env;
use std::error::Error;

#[derive(Debug, Deserialize, Serialize)]
struct Record {
    id: i64,
    category: String,
    clicks: Option<f64>, // BUG: Lazily using float for NaN semantics
    response_time: f64,
}

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: {} <input.csv> <output.csv>", args[0]);
        std::process::exit(1);
    }

    let mut rdr = Reader::from_path(&args[1])?;
    let mut wtr = Writer::from_path(&args[2])?;

    for result in rdr.deserialize() {
        let mut record: Record = result?;

        // If it's missing, it stays None, but serializes empty.
        // We want it to be -1 integer.

        wtr.serialize(record)?;
    }
    wtr.flush()?;
    Ok(())
}
EOF

    chmod -R 777 /home/user
