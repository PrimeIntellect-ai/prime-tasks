#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo curl
    pip3 install pytest

    mkdir -p /home/user/dataset_organizer/data
    mkdir -p /home/user/dataset_organizer/src

    # Create dataset using bash to support brace expansion
    bash -c '
    for i in {0..99}; do
      row=""
      for j in {0..4}; do
        val=$((i * 10 + j))
        if [ $j -eq 0 ]; then
          row="$val"
        else
          row="$row,$val"
        fi
      done
      echo "$row" >> /home/user/dataset_organizer/data/embeddings.csv
    done
    '

    cat << 'EOF' > /home/user/dataset_organizer/Cargo.toml
[package]
name = "dataset_organizer"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/dataset_organizer/src/main.rs
use std::fs::File;
use std::io::{BufRead, BufReader};

fn main() {
    let file = File::open("data/embeddings.csv").expect("Failed to open file");
    let reader = BufReader::new(file);

    let mut data: Vec<Vec<f64>> = Vec::new();

    for line in reader.lines() {
        let line = line.expect("Failed to read line");
        let row: Vec<f64> = line
            .split(',')
            .map(|s| s.parse().expect("Failed to parse float"))
            .collect();
        data.push(row);
    }

    let num_rows = data.len();
    let num_cols = data[0].len();

    // BUG: Data leakage! Calculating mean over the whole dataset before splitting
    let mut means = vec![0.0; num_cols];
    for row in &data {
        for j in 0..num_cols {
            means[j] += row[j];
        }
    }
    for j in 0..num_cols {
        means[j] /= num_rows as f64;
    }

    // Transforming entire dataset
    let mut transformed_data = data.clone();
    for i in 0..num_rows {
        for j in 0..num_cols {
            transformed_data[i][j] -= means[j];
        }
    }

    // Splitting after transformation
    let _train_set = transformed_data[0..80].to_vec();
    let test_set = transformed_data[80..100].to_vec();

    // Calculate sum of test set
    let mut test_sum = 0.0;
    for row in &test_set {
        for val in row {
            test_sum += val;
        }
    }

    println!("Test sum: {:.4}", test_sum);
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/dataset_organizer
    chmod -R 777 /home/user
