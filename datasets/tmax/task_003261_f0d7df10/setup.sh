#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl tesseract-ocr imagemagick
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    export PATH="/root/.cargo/bin:$PATH"

    # Create policy image
    mkdir -p /app
    # Fix ImageMagick policy to allow text/xc operations if needed, or just use it
    convert -size 400x100 xc:white -fill black -pointsize 24 -annotate +10+50 '>=1.2.0 <2.0.0' /app/policy.png

    # Create Rust project
    mkdir -p /home/user/policy-service/src
    cat << 'EOF' > /home/user/policy-service/Cargo.toml
[package]
name = "policy-service"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tokio = { version = "1.0", features = ["full"] }
axum = "0.6"
proptest = "1.0"
EOF

    cat << 'EOF' > /home/user/policy-service/src/main.rs
mod semver;

fn main() {
    println!("Hello, world!");
}
EOF

    cat << 'EOF' > /home/user/policy-service/src/semver.rs
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Version {
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
}

impl PartialOrd for Version {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Version {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        if self.major != other.major {
            self.major.cmp(&other.major)
        } else {
            // BUG: skips minor version comparison
            self.patch.cmp(&other.patch)
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/policy-service
    chmod -R 777 /home/user
    chmod -R 777 /app
