#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/risk_engine/src
mkdir -p /home/user/risk_engine/libs/common_types_v1/src
mkdir -p /home/user/risk_engine/libs/common_types_v2/src
mkdir -p /home/user/risk_engine/libs/math_utils/src

# 1. Memory Dump Mock
dd if=/dev/urandom of=/home/user/risk_engine/crash.dump bs=1K count=1024 2>/dev/null
echo -e "\x00\x01\x02FATAL_ERROR_PROCESSING_CRITICAL_TXID:TXID-84729-OMEGA_BUFFER_OVERFLOW\x00\x01" >> /home/user/risk_engine/crash.dump
dd if=/dev/urandom bs=1K count=1024 >> /home/user/risk_engine/crash.dump 2>/dev/null

# 2. Workspace and Crates Setup
cat << 'EOF' > /home/user/risk_engine/Cargo.toml
[package]
name = "risk_engine"
version = "0.1.0"
edition = "2021"

[dependencies]
common_types = { path = "./libs/common_types_v2" }
math_utils = { path = "./libs/math_utils" }
EOF

cat << 'EOF' > /home/user/risk_engine/libs/common_types_v1/Cargo.toml
[package]
name = "common_types"
version = "1.0.0"
edition = "2021"
EOF

cat << 'EOF' > /home/user/risk_engine/libs/common_types_v1/src/lib.rs
#[derive(Debug, Clone, PartialEq)]
pub struct Transaction {
    pub id: String,
    pub amount: f64,
}
EOF

cat << 'EOF' > /home/user/risk_engine/libs/common_types_v2/Cargo.toml
[package]
name = "common_types"
version = "2.0.0"
edition = "2021"
EOF

cat << 'EOF' > /home/user/risk_engine/libs/common_types_v2/src/lib.rs
#[derive(Debug, Clone, PartialEq)]
pub struct Transaction {
    pub id: String,
    pub amount: f64,
    pub metadata: String, // Added in v2
}
EOF

cat << 'EOF' > /home/user/risk_engine/libs/math_utils/Cargo.toml
[package]
name = "math_utils"
version = "0.1.0"
edition = "2021"

[dependencies]
common_types = { path = "../common_types_v1" }
EOF

cat << 'EOF' > /home/user/risk_engine/libs/math_utils/src/lib.rs
use common_types::Transaction;

pub fn validate_transaction(tx: &Transaction) -> bool {
    tx.amount > 0.0
}
EOF

# 3. Main Application Code
cat << 'EOF' > /home/user/risk_engine/src/main.rs
use common_types::Transaction;
use math_utils::validate_transaction;
use std::env;

fn calculate_risk_score(base_amount: f64, iterations: u32) -> f64 {
    // BUG: Precision loss due to f32
    let mut risk: f32 = base_amount as f32;
    for _ in 0..iterations {
        risk *= 1.01_f32;
    }
    risk as f64
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: risk_engine <TXID>");
        std::process::exit(1);
    }
    let tx_id = &args[1];

    let tx = Transaction {
        id: tx_id.clone(),
        amount: 1000.0,
    };

    if validate_transaction(&tx) {
        let score = calculate_risk_score(tx.amount, 365);
        println!("{}", score);
    } else {
        println!("Invalid transaction");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculate_risk_score() {
        let score = calculate_risk_score(1000.0, 365);
        // The expected f64 precision result
        assert!((score - 37783.43433288728).abs() < 1e-5, "Precision error: got {}", score);
    }
}
EOF

chown -R user:user /home/user/risk_engine
chmod -R 777 /home/user
