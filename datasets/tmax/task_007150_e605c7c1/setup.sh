#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo
pip3 install pytest

mkdir -p /home/user/min_tool/src

cat << 'EOF' > /home/user/min_tool/Cargo.toml
[package]
name = "min_tool"
version = "0.1.0"
edition = "2021"

[dependencies]
semver = "0.9.0" # intentionally old version to cause compile error with 1.0 API
EOF

cat << 'EOF' > /home/user/min_tool/src/main.rs
use semver::{Version, VersionReq};
use std::time::Instant;
use std::fs::File;
use std::io::Write;
use core::arch::asm;

// Extract vendor ID from ebx, edx, ecx using cpuid (eax=0).
fn cpuid_vendor() -> [u8; 12] {
    // TODO: Implement using inline assembly. 
    // Return the 12 byte vendor string.
    [0; 12]
}

fn main() {
    // This API requires semver 1.0+
    let req = VersionReq::parse(">=1.0.0, <2.0.0").unwrap();
    let ver = Version::parse("1.5.0").unwrap();
    let semver_check = req.matches(&ver);

    let start = Instant::now();
    for _ in 0..10_000 {
        let _ = cpuid_vendor();
    }
    let elapsed = start.elapsed().as_nanos();

    let vendor_bytes = cpuid_vendor();
    let vendor_str = String::from_utf8_lossy(&vendor_bytes).into_owned();

    let json = format!(
        "{}\"vendor\": \"{}\", \"semver_check\": {}, \"bench_success\": {}{}",
        "{",
        vendor_str,
        semver_check,
        elapsed > 0,
        "}"
    );

    let mut file = File::create("/home/user/result.json").unwrap();
    file.write_all(json.as_bytes()).unwrap();
    println!("Done. Check /home/user/result.json");
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
