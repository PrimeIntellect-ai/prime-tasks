#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl build-essential espeak
    pip3 install pytest

    # Generate audio file
    mkdir -p /app
    espeak -w /app/intercepted_comms.wav "the quick brown fox jumps over the lazy dog"

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Setup Git repository
    mkdir -p /home/user/repo
    cd /home/user/repo
    cargo new audio-svc
    cd audio-svc

    git init
    git config user.email "researcher@example.com"
    git config user.name "Security Researcher"

    cat << 'EOF' > Cargo.toml
[package]
name = "audio-svc"
version = "0.1.0"
edition = "2021"

[dependencies]
axum = "0.6"
tokio = { version = "1", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > src/main.rs
mod smoothing;

fn main() {
    println!("Service ready.");
}
EOF

    cat << 'EOF' > src/smoothing.rs
pub fn smooth_signal(data: Vec<f64>) -> Vec<f64> {
    let mut result = Vec::new();
    for mut val in data {
        while val > 0.0 {
            val -= 0.1;
        }
        result.push(val);
    }
    result
}
EOF

    git add .
    git commit -m "Initial commit with smoothing module"

    for i in {1..3}; do
        echo "// Refactoring step $i" >> src/smoothing.rs
        git commit -am "Minor refactor $i"
    done

    # Introduce the bad commit
    cat << 'EOF' > src/smoothing.rs
pub fn smooth_signal(data: Vec<f64>) -> Vec<f64> {
    let mut result = Vec::new();
    for mut val in data {
        while val != 0.0 {
            val -= 0.1;
        }
        result.push(val);
    }
    result
}
EOF
    git commit -am "Optimize smoothing loop condition"

    for i in {4..7}; do
        echo "// Additional comment $i" >> src/smoothing.rs
        git commit -am "Add comments $i"
    done

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
