#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust system-wide
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/cargo/bin:$PATH"
    chmod -R 777 /opt/rust /opt/cargo

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup directories
    mkdir -p /home/user/crash_logs
    mkdir -p /home/user/trade_analyzer/src

    # Create the log file
    cat << 'EOF' > /home/user/crash_logs/prod-analyzer-01.log
[2023-10-27T02:55:01Z INFO  analyzer] Processing tx_id: TX-11234
[2023-10-27T02:55:02Z INFO  analyzer] Processing tx_id: TX-11235
[2023-10-27T02:55:03Z INFO  analyzer] Processing tx_id: TX-99842
[2023-10-27T02:55:03Z ERROR analyzer] thread 'main' panicked at 'attempt to divide by zero', src/vwap.rs:14:5
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
[2023-10-27T02:55:03Z FATAL container] Container prod-analyzer-01 exited with code 101
EOF

    # Create the Rust project files
    cat << 'EOF' > /home/user/trade_analyzer/Cargo.toml
[package]
name = "trade_analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
clap = { version = "4.4", features = ["derive"] }
thiserror = "=99.0.0" # Intentional conflict/bad version
EOF

    cat << 'EOF' > /home/user/trade_analyzer/src/main.rs
use clap::Parser;
mod vwap;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    #[arg(short, long)]
    tx: String,
}

fn main() {
    let args = Args::parse();

    // Mocking the database fetch for the transaction
    let trades = if args.tx == "TX-99842" {
        vec![
            vwap::Trade { price: 150.0, volume: 0 },
            vwap::Trade { price: 155.0, volume: 0 },
        ]
    } else {
        vec![
            vwap::Trade { price: 100.0, volume: 10 },
            vwap::Trade { price: 110.0, volume: 5 },
        ]
    };

    let result = vwap::calculate_vwap(&trades);
    println!("{result}");
}
EOF

    cat << 'EOF' > /home/user/trade_analyzer/src/vwap.rs
pub struct Trade {
    pub price: f64,
    pub volume: u32,
}

pub fn calculate_vwap(trades: &[Trade]) -> f64 {
    let mut total_value = 0.0;
    let mut total_volume = 0;

    for trade in trades {
        total_value += trade.price * (trade.volume as f64);
        total_volume += trade.volume;
    }

    // BUG: Division by zero if total_volume is 0
    total_value / (total_volume as f64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normal_vwap() {
        let trades = vec![
            Trade { price: 10.0, volume: 100 },
            Trade { price: 20.0, volume: 100 },
        ];
        assert_eq!(calculate_vwap(&trades), 15.0);
    }

    #[test]
    fn test_zero_volume_vwap() {
        let trades = vec![
            Trade { price: 150.0, volume: 0 },
            Trade { price: 155.0, volume: 0 },
        ];
        assert_eq!(calculate_vwap(&trades), 0.0);
    }
}
EOF

    chmod -R 777 /home/user
