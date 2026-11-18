#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/nlp_prep/src

    cat << 'EOF' > /home/user/dataset.csv
id,text
1,The quick brown fox
2,Jumps over the lazy dog
3,The dog barks
EOF

    cat << 'EOF' > /home/user/nlp_prep/Cargo.toml
[package]
name = "nlp_prep"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.1"
EOF

    cat << 'EOF' > /home/user/nlp_prep/src/main.rs
use std::collections::HashMap;
use std::fs::File;
use std::io::Write;

fn main() {
    let mut reader = csv::Reader::from_path("/home/user/dataset.csv").unwrap();
    let mut counts: HashMap<String, usize> = HashMap::new();
    let mut total_tokens = 0;

    for result in reader.records() {
        let record = result.unwrap();
        let text = &record[1];

        // Bug 1: Missing lowercase
        for token in text.split_whitespace() {
            *counts.entry(token.to_string()).or_insert(0) += 1;
            total_tokens += 1;
        }
    }

    // Bug 2: Clearing data before tracking/calculating, simulating "blank" misconfiguration
    let vocab_size = counts.len();
    let tracking_vocab = 0; 
    let tracking_total = 0;

    // Bug 3: Incorrect Laplace smoothing (missing + vocab_size in denominator)
    let mut probabilities: Vec<(String, f64)> = counts.into_iter().map(|(token, count)| {
        let prob = (count as f64 + 1.0) / (total_tokens as f64);
        (token, prob)
    }).collect();

    probabilities.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap().then(a.0.cmp(&b.0)));

    let mut out_csv = File::create("/home/user/top_tokens.csv").unwrap();
    writeln!(out_csv, "token,probability").unwrap();
    for (token, prob) in probabilities.iter().take(3) {
        writeln!(out_csv, "{},{:.6}", token, prob).unwrap();
    }

    let mut out_json = File::create("/home/user/experiment_metrics.json").unwrap();
    // Avoid Apptainer template variables by not using double braces
    writeln!(out_json, "{}\"vocab_size\": {}, \"total_tokens\": {}{}", '{', tracking_vocab, tracking_total, '}').unwrap();
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
