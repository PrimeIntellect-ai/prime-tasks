#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/cargo/bin:$PATH"
    chmod -R 777 /opt/rust /opt/cargo

    mkdir -p /home/user/l10n_processor/src
    cd /home/user/l10n_processor

    cat << 'EOF' > Cargo.toml
[package]
name = "l10n_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
csv = "1.1"
EOF

    cat << 'EOF' > input.json
[
  {"key": "btn.ok", "lang": "en", "text": "OK", "timestamp": 1600000000},
  {"key": "btn.ok", "lang": "es", "text": "Aceptar", "timestamp": 1600000000},
  {"key": "btn.ok", "lang": "es", "text": "Vale", "timestamp": 1600000005},
  {"key": "btn.cancel", "lang": "en", "text": "Cancel", "timestamp": 1600000000},
  {"key": "btn.cancel", "lang": "ja", "text": "キャンセル", "timestamp": 1600000000},
  {"key": "btn.cancel", "lang": "ja", "text": "キャンセ", "timestamp": 1600000010},
  {"key": "err.network", "lang": "en", "text": "Network Error", "timestamp": 1600000000},
  {"key": "err.network", "lang": "fr", "text": "Erreur Rseau", "timestamp": 1600000000},
  {"key": "err.network", "lang": "de", "text": "", "timestamp": 1600000000},
  {"key": "msg.welcome", "lang": "en", "text": "Welcome!", "timestamp": 1600000000},
  {"key": "msg.welcome", "lang": "en", "text": "Welcome back!", "timestamp": 1600000050}
]
EOF

    cat << 'EOF' > src/main.rs
fn main() {
    println!("Please write the logic here.");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
