#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl acl cargo rustc sudo
pip3 install pytest

# Create users
useradd -m -s /bin/bash user || true
useradd -m -s /bin/bash otheruser || true

# Setup secure logs
mkdir -p /app/secure_logs

# Generate a ~50MB log file
python3 -c '
with open("/app/secure_logs/router.log", "w") as f:
    for i in range(1200000):
        f.write(f"EVENT {i}: Normal routing operation\n")
    f.write("EVENT 1200001: TIMEOUT occurred\n")
'

chown -R otheruser:otheruser /app/secure_logs
chmod 700 /app/secure_logs
chmod 700 /app/secure_logs/router.log

# Allow user to run setfacl via sudo if needed, or just rely on the test environment's capabilities
echo "user ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Setup net-analyzer
mkdir -p /app/vendored/net-analyzer/src

cat << 'EOF' > /app/vendored/net-analyzer/Cargo.toml
[package]
name = "net-analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /app/vendored/net-analyzer/src/main.rs
use std::fs::File;
use std::io::Read;
use std::env;

fn main() {
    let _ = std::fs::write("/tmp/analyzer.health", "OK");
    let path = env::var("ROUTER_LOG_PATH").unwrap_or_else(|_| "/nonexistent/default.log".to_string());
    let mut file = File::open(path).expect("Failed to open file");
    let mut content = String::new();
    let mut buf = [0; 1];
    while let Ok(n) = file.read(&mut buf) {
        if n == 0 { break; }
        let c = buf[0] as char;
        content.push(c);
        if content.ends_with("TIMEOUT") {
            panic!("Unexpected format");
        }
    }
}
EOF

chown -R user:user /app/vendored
chmod -R 755 /app/vendored

# Ensure .bashrc exists
touch /home/user/.bashrc
chown user:user /home/user/.bashrc

chmod -R 777 /home/user
