#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/ml_prep/src

    cat << 'EOF' > /home/user/data/users.csv
user_id,name
1,Alice
2,Bob
3,Charlie
EOF

    cat << 'EOF' > /home/user/data/features.csv
user_id,f1,f2,f3
1,1.0,,3.0
2,,2.0,2.0
3,1.5,1.5,
EOF

    cat << 'EOF' > /home/user/ml_prep/Cargo.toml
[package]
name = "ml_prep"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/ml_prep/src/main.rs
use std::fs;

fn main() {
    let features_data = fs::read_to_string("/home/user/data/features.csv").unwrap();
    let mut features: Vec<Vec<f64>> = Vec::new();

    for (i, line) in features_data.lines().enumerate() {
        if i == 0 { continue; }
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() == 4 {
            let f1 = parts[1].parse::<f64>().unwrap_or(std::f64::NAN);
            let f2 = parts[2].parse::<f64>().unwrap_or(std::f64::NAN);
            let f3 = parts[3].parse::<f64>().unwrap_or(std::f64::NAN);
            features.push(vec![f1, f2, f3]);
        }
    }

    let mut out = String::new();
    for i in 0..features.len() {
        let mut row = Vec::new();
        for j in 0..features.len() {
            let dot = features[i][0] * features[j][0] 
                    + features[i][1] * features[j][1] 
                    + features[i][2] * features[j][2];
            row.push(dot.to_string());
        }
        out.push_str(&row.join(","));
        out.push('\n');
    }

    fs::write("/home/user/ml_prep/similarity.csv", out).unwrap();
}
EOF

    chmod -R 777 /home/user
