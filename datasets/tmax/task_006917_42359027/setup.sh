#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/stats_project/src

    cat << 'EOF' > /home/user/stats_project/Cargo.toml
[package]
name = "stats_project"
version = "0.1.0"
edition = "2021"

[dependencies]
rand = "0.8"
log = "0.4"
env_logger = "0.10"
EOF

    cat << 'EOF' > /home/user/stats_project/src/lib.rs
use rand::{Rng, SeedableRng};
use rand::rngs::SmallRng;
use log::{info, error};

pub fn compute_variance(data: &[f64]) -> f64 {
    let mean = data.iter().sum::<f64>() / data.len() as f64;
    let mean_sq = data.iter().map(|&x| x * x).sum::<f64>() / data.len() as f64;

    // BUG: The formula for variance is E[X^2] - (E[X])^2, but this is flipped.
    let var = mean.powi(2) - mean_sq;

    var
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_statistical_anomaly() {
        let _ = env_logger::builder().is_test(true).try_init();
        let mut rng = SmallRng::seed_from_u64(42);
        let mut data = vec![];
        for _ in 0..100 {
            data.push(rng.gen_range(-10.0..10.0));
        }

        let var = compute_variance(&data);
        info!("Computed variance: {}", var);

        let std_dev = var.sqrt();
        info!("Computed std_dev: {}", std_dev);

        assert!(std_dev > 4.0 && std_dev < 7.0, "Statistical anomaly detected: std_dev is {}", std_dev);
    }
}
EOF

    chmod -R 777 /home/user
