#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest pandas numpy

    mkdir -p /app/data
    mkdir -p /app/linreg_pipeline/src

    # Generate data
    cat << 'EOF' > /tmp/gen_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n = 100
id = np.arange(n)
f1 = np.random.randn(n)
f2 = np.random.randint(1, 10, size=n)
target = 2.0 * f1 + 3.0 * f2 + np.random.randn(n) * 0.1

# Introduce missing values in f2
f2_str = f2.astype(str)
missing_indices = np.random.choice(n, 20, replace=False)
f2_str[missing_indices] = ""

df_f = pd.DataFrame({"id": id, "f1": f1, "f2": f2_str})
df_t = pd.DataFrame({"id": id, "target": target})

df_f.to_csv("/app/data/features.csv", index=False)
df_t.to_csv("/app/data/targets.csv", index=False)
df_t.to_csv("/app/data/test_targets_hidden.csv", index=False)
EOF
    python3 /tmp/gen_data.py

    # Create Rust project
    cat << 'EOF' > /app/linreg_pipeline/Cargo.toml
[package]
name = "linreg_pipeline"
version = "0.1.0"
edition = "2021"

[dependencies]
csv = "1.3"
serde = { version = "1.0", features = ["derive"] }
EOF

    cat << 'EOF' > /app/linreg_pipeline/src/main.rs
use std::error::Error;
use csv::ReaderBuilder;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct FeatureRow {
    id: u32,
    f1: f64,
    #[serde(default)]
    f2: i32, // Missing values become 0, ruining the model
}

#[derive(Debug, Deserialize)]
struct TargetRow {
    id: u32,
    target: f64,
}

fn solve(x: &Vec<[f64; 2]>, y: &Vec<f64>) -> [f64; 2] {
    let mut xtx = [[0.0; 2]; 2];
    let mut xty = [0.0; 2];
    for i in 0..x.len() {
        xtx[0][0] += x[i][0] * x[i][0];
        xtx[0][1] += x[i][0] * x[i][1];
        xtx[1][0] += x[i][1] * x[i][0];
        xtx[1][1] += x[i][1] * x[i][1];
        xty[0] += x[i][0] * y[i];
        xty[1] += x[i][1] * y[i];
    }
    let det = xtx[0][0] * xtx[1][1] - xtx[0][1] * xtx[1][0];
    let inv = [[xtx[1][1] / det, -xtx[0][1] / det], [-xtx[1][0] / det, xtx[0][0] / det]];
    let w0 = inv[0][0] * xty[0] + inv[0][1] * xty[1];
    let w1 = inv[1][0] * xty[0] + inv[1][1] * xty[1];
    [w0, w1]
}

fn main() -> Result<(), Box<dyn Error>> {
    let mut f_rdr = ReaderBuilder::new().from_path("/app/data/features.csv")?;
    let mut t_rdr = ReaderBuilder::new().from_path("/app/data/targets.csv")?;

    let mut features = Vec::new();
    for result in f_rdr.deserialize() {
        let record: FeatureRow = result?;
        features.push(record);
    }

    let mut targets = Vec::new();
    for result in t_rdr.deserialize() {
        let record: TargetRow = result?;
        targets.push(record);
    }

    let mut x = Vec::new();
    let mut y = Vec::new();
    let mut ids = Vec::new();

    for f in features {
        if let Some(t) = targets.iter().find(|t| t.id == f.id) {
            x.push([f.f1, f.f2 as f64]);
            y.push(t.target);
            ids.push(f.id);
        }
    }

    let w = solve(&x, &y);

    let mut wtr = csv::Writer::from_path("/app/linreg_pipeline/predictions.csv")?;
    wtr.write_record(&["id", "prediction"])?;
    for (i, id) in ids.iter().enumerate() {
        let pred = w[0] * x[i][0] + w[1] * x[i][1];
        wtr.write_record(&[id.to_string(), pred.to_string()])?;
    }
    wtr.flush()?;

    Ok(())
}
EOF

    cd /app/linreg_pipeline && cargo build

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
