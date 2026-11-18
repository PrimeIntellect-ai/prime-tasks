#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential pkg-config libfontconfig1-dev
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /home/user/rust-etl/src
    cd /home/user/rust-etl

    # Generate data.csv
    python3 -c '
import numpy as np
import pandas as pd

np.random.seed(42)
n_samples = 200
X_corr = np.random.randn(n_samples, 3)
y = X_corr[:, 0] * 3.0 + X_corr[:, 1] * 2.0 + X_corr[:, 2] * 1.0 + np.random.randn(n_samples) * 0.5

X_noise = np.random.randn(n_samples, 7)
X = np.hstack([X_corr, X_noise])

df = pd.DataFrame(X, columns=[f"f{i}" for i in range(10)])
df["target"] = y
df.to_csv("data.csv", index=False)
'

    cat << 'EOF' > Cargo.toml
[package]
name = "rust-etl"
version = "0.1.0"
edition = "2021"

[dependencies]
linfa = "0.7.0"
linfa-pca = "0.7.0"
linfa-linear = "0.7.0"
ndarray = "0.15.6"
ndarray-csv = "0.5.2"
csv = "1.1"
plotters = "0.3.5"
serde_json = "1.0"
EOF

    cat << 'EOF' > src/main.rs
use linfa::prelude::*;
use linfa_pca::Pca;
use linfa_linear::LinearRegression;
use ndarray::Array2;
use csv::ReaderBuilder;
use ndarray_csv::Array2Reader;
use plotters::prelude::*;
use std::fs::File;

fn main() {
    let mse = run_pipeline();
    println!("MSE: {}", mse);
    // TODO: Write metrics.json
}

fn run_pipeline() -> f64 {
    let file = File::open("data.csv").unwrap();
    let mut reader = ReaderBuilder::new().has_headers(true).from_reader(file);
    let data: Array2<f64> = reader.deserialize_array2_dynamic().unwrap();

    let features = data.slice(ndarray::s![.., 0..10]).to_owned();
    let targets = data.slice(ndarray::s![.., 10]).to_owned();

    let dataset = Dataset::new(features, targets);

    let pca = Pca::params(1).fit(&dataset).unwrap();
    let transformed = pca.predict(&dataset);

    let model = LinearRegression::new().fit(&transformed).unwrap();
    let predictions = model.predict(&transformed);

    let mse = transformed.targets.iter().zip(predictions.iter())
        .map(|(y, y_pred)| (y - y_pred).powi(2))
        .sum::<f64>() / transformed.targets.len() as f64;

    let root = BitMapBackend::new("plot.png", (640, 480)).into_drawing_area();
    root.fill(&WHITE).unwrap();
    let mut chart = ChartBuilder::on(&root)
        .build_cartesian_2d(-10f64..10f64, -10f64..10f64).unwrap();

    chart.configure_mesh().draw().unwrap();
    // BUG: Missing root.present().unwrap();

    mse
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_numerical_accuracy() {
        let mse = run_pipeline();
        assert!(mse < 2.0, "MSE is too high: {}", mse);
    }
}
EOF

    # Fix permissions and copy rust to user
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup
    chown -R user:user /home/user
    chmod -R 777 /home/user
