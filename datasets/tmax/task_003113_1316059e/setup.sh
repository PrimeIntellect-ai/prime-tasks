#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo espeak
pip3 install pytest

mkdir -p /app/data
mkdir -p /app/vuln_dashboard/lib
mkdir -p /app/vuln_dashboard/src

espeak -w /app/voicemail.wav "Hey, I had to leave early. The CI is failing because the build script isn't linking the secutils library. Also, the new bearer token for the dashboard API is SuperSecretDragon99. Good luck."

cat << 'EOF' > /app/data/raw_vulns.json
[
  {"cve_id": "CVE-2023-0002", "severity": "MEDIUM", "affected_endpoints": ["/api/users"]},
  {"cve_id": "CVE-2023-0001", "severity": "CRITICAL", "affected_endpoints": ["/login"]},
  {"cve_id": "CVE-2023-0002", "severity": "MEDIUM", "affected_endpoints": ["/api/profile"]},
  {"cve_id": "CVE-2024-1111", "severity": "HIGH", "affected_endpoints": ["/admin"]}
]
EOF

cat << 'EOF' > /app/vuln_dashboard/Cargo.toml
[package]
name = "vuln_dashboard"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cat << 'EOF' > /app/vuln_dashboard/build.rs
fn main() {
    // Missing linkage
}
EOF

touch /app/vuln_dashboard/lib/libsecutils.a

cat << 'EOF' > /app/vuln_dashboard/src/main.rs
mod processor;

fn main() {
    println!("Hello, world!");
}
EOF

cat << 'EOF' > /app/vuln_dashboard/src/processor.rs
pub fn process() {
    // TODO
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
