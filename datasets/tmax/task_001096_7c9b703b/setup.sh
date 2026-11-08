#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl build-essential
pip3 install pytest

# Install Rust minimally
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
chmod -R a+rwX /opt/rust /opt/cargo
ln -s /opt/cargo/bin/* /usr/local/bin/

# Create the score_oracle binary
mkdir -p /app
cat << 'EOF' > /tmp/score_oracle.rs
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        std::process::exit(1);
    }
    let mu: f64 = args[1].parse().unwrap();
    let log_lik = - (mu - 1.234).powi(2) / (2.0 * 0.1_f64.powi(2));
    println!("{}", log_lik);
}
EOF

rustc -O /tmp/score_oracle.rs -o /app/score_oracle
strip /app/score_oracle
chmod +x /app/score_oracle

# Create user
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
