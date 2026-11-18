#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/etl_pipeline/src
    cd /home/user/etl_pipeline

    cat << 'EOF' > Cargo.toml
[package]
name = "etl_pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > data.csv
id,text,value,is_train
1,hello world,10.0,true
2,hello rust,20.0,true
3,rust is fast,30.0,true
4,hello python,100.0,false
5,fast python,110.0,false
EOF

    cat << 'EOF' > src/main.rs
use std::collections::{BTreeSet, HashMap};
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

#[derive(Debug)]
struct Row {
    id: String,
    text: String,
    value: f64,
    is_train: bool,
}

fn main() {
    let file = File::open("data.csv").expect("Cannot open data.csv");
    let reader = BufReader::new(file);
    let mut rows = Vec::new();

    for (i, line) in reader.lines().enumerate() {
        if i == 0 { continue; } // skip header
        let l = line.unwrap();
        let parts: Vec<&str> = l.split(',').collect();
        rows.push(Row {
            id: parts[0].to_string(),
            text: parts[1].to_string(),
            value: parts[2].parse().unwrap(),
            is_train: parts[3] == "true",
        });
    }

    // BUG: Computing stats over the entire dataset!
    let total_count = rows.len() as f64;
    let mean = rows.iter().map(|r| r.value).sum::<f64>() / total_count;
    let variance = rows.iter().map(|r| (r.value - mean).powi(2)).sum::<f64>() / (total_count - 1.0);
    let std_dev = variance.sqrt();

    // BUG: Building vocabulary over the entire dataset!
    let mut vocab = BTreeSet::new();
    for r in &rows {
        for word in r.text.split_whitespace() {
            vocab.insert(word.to_string());
        }
    }
    let vocab: Vec<String> = vocab.into_iter().collect();

    let mut train_out = File::create("output_train.csv").unwrap();
    let mut test_out = File::create("output_test.csv").unwrap();

    let header = format!("id,scaled_value,{}\n", vocab.join(","));
    train_out.write_all(header.as_bytes()).unwrap();
    test_out.write_all(header.as_bytes()).unwrap();

    for r in rows {
        let scaled_val = (r.value - mean) / std_dev;

        let mut counts = HashMap::new();
        for word in r.text.split_whitespace() {
            *counts.entry(word.to_string()).or_insert(0) += 1;
        }

        let mut row_str = format!("{},{:.4}", r.id, scaled_val);
        for v in &vocab {
            let count = counts.get(v).unwrap_or(&0);
            row_str.push_str(&format!(",{}", count));
        }
        row_str.push('\n');

        if r.is_train {
            train_out.write_all(row_str.as_bytes()).unwrap();
        } else {
            test_out.write_all(row_str.as_bytes()).unwrap();
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
