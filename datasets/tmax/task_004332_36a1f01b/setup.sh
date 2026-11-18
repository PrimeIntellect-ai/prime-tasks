#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /opt/rust /opt/cargo

    mkdir -p /home/user/dataset_processor/src

    cat << 'EOF' > /home/user/dataset_processor/Cargo.toml
[package]
name = "dataset_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/dataset_processor/src/main.rs
mod processor;

fn main() {
    let data = vec![10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 100.0, 110.0];
    let res = processor::process_data(&data, 6);
    println!("{:.4}", res);
}
EOF

    cat << 'EOF' > /home/user/dataset_processor/src/processor.rs
pub fn normalize(data: &[f64], mean: f64, std: f64) -> Vec<f64> {
    data.iter().map(|&x| (x - mean) / std).collect()
}

pub fn calculate_mean(data: &[f64]) -> f64 {
    data.iter().sum::<f64>() / data.len() as f64
}

pub fn calculate_std(data: &[f64], mean: f64) -> f64 {
    let variance = data.iter().map(|&x| (x - mean).powi(2)).sum::<f64>() / data.len() as f64;
    variance.sqrt()
}

pub fn process_data(all_data: &[f64], split_index: usize) -> f64 {
    // BUG: Data Leak
    let mean = calculate_mean(all_data);
    let std = calculate_std(all_data, mean);

    let normalized = normalize(all_data, mean, std);
    let test_normalized = &normalized[split_index..];

    test_normalized.iter().sum::<f64>()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_process_data_no_leak() {
        let data = vec![10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 100.0, 110.0];
        let result = process_data(&data, 6);
        assert!((result - 52.6986).abs() < 0.01, "Expected ~52.6986 without leak, got {}", result);
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
