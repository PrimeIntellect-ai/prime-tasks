#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/target_encoder
    cd /home/user/target_encoder
    cargo init

    cat << 'EOF' > /home/user/dataset.csv
id,category,target
1,A,1.0
2,B,0.0
3,A,1.0
4,C,0.0
5,A,0.0
6,B,1.0
7,B,1.0
8,C,0.0
9,A,1.0
10,D,1.0
EOF

    cat << 'EOF' > /home/user/target_encoder/src/main.rs
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader, Write};

fn main() {
    let file = File::open("/home/user/dataset.csv").unwrap();
    let reader = BufReader::new(file);
    let mut lines = reader.lines().skip(1); // skip header

    let mut data = Vec::new();
    let mut sum_target = 0.0;
    let mut counts = HashMap::new();
    let mut sums = HashMap::new();

    for line in lines {
        let l = line.unwrap();
        let parts: Vec<&str> = l.split(',').collect();
        let id = parts[0].to_string();
        let cat = parts[1].to_string();
        let target: f64 = parts[2].parse().unwrap();

        data.push((id, cat.clone(), target));
        sum_target += target;
        *counts.entry(cat.clone()).or_insert(0.0) += 1.0;
        *sums.entry(cat.clone()).or_insert(0.0) += target;
    }

    let global_mean = sum_target / data.len() as f64;
    let prior_weight = 10.0;

    let mut encoded_data = Vec::new();
    for (id, cat, target) in &data {
        let count = counts.get(cat).unwrap();
        let sum = sums.get(cat).unwrap();
        let cat_mean = sum / count;

        let encoded = (count * cat_mean + prior_weight * global_mean) / (count + prior_weight);
        encoded_data.push((id.clone(), cat.clone(), *target, encoded));
    }

    let split_idx = (encoded_data.len() as f64 * 0.8) as usize;
    let (train, test) = encoded_data.split_at(split_idx);

    let mut train_out = File::create("/home/user/train_encoded.csv").unwrap();
    writeln!(train_out, "id,category,target,encoded_feature").unwrap();
    for (id, cat, t, e) in train {
        writeln!(train_out, "{},{},{},{:.4}", id, cat, t, e).unwrap();
    }

    let mut test_out = File::create("/home/user/test_encoded.csv").unwrap();
    writeln!(test_out, "id,category,target,encoded_feature").unwrap();
    for (id, cat, t, e) in test {
        writeln!(test_out, "{},{},{},{:.4}", id, cat, t, e).unwrap();
    }
}
EOF

    chmod -R 777 /home/user
