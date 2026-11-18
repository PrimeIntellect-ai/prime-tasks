#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/input.csv
id,text
1,"The connection timed out and threw an error."
2,"Success! We managed to connect."
3,"System fail, timeout occurred."
4,"All good."
5,"error error fail"
6,"connect connect connect"
7,"Warning: timeout on connect."
8,"Critical error, fail to connect."
9,"success, success, success"
10,"Unknown issue."
EOF

    mkdir -p /home/user/etl_pipeline/src
    cat << 'EOF' > /home/user/etl_pipeline/Cargo.toml
[package]
name = "etl_pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/etl_pipeline/src/main.rs
use std::error::Error;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

fn main() -> Result<(), Box<dyn Error>> {
    let input = File::open("/home/user/data/input.csv")?;
    let reader = BufReader::new(input);

    let mut output = File::create("/home/user/data/output.csv")?;
    writeln!(output, "id,prob,prediction")?;

    let keywords = ["error", "fail", "timeout", "success", "connect"];
    let weights = [1.2, 0.8, 0.5, -1.0, 0.3];
    let bias = -0.5;

    for line in reader.lines().skip(1) {
        let line = line?;
        // BUG: incorrect CSV splitting and hardcoded empty text
        let parts: Vec<&str> = line.split(',').collect();
        if parts.is_empty() { continue; }
        let id = parts[0];
        let text = ""; // Bug: blank plots/embeddings issue

        let mut emb = [0.0; 5];
        for (i, &kw) in keywords.iter().enumerate() {
            emb[i] = text.to_lowercase().matches(kw).count() as f64;
        }

        let mut logit = bias;
        for i in 0..5 {
            logit += emb[i] * weights[i];
        }

        let prob = 1.0 / (1.0 + (-logit).exp());
        let pred = if prob > 0.5 { 1 } else { 0 };

        writeln!(output, "{},{},{}", id, prob, pred)?;
    }

    Ok(())
}
EOF

    # Make rust available to user
    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
