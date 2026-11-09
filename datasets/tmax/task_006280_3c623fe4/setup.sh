#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    # 1. Create directories
    mkdir -p /home/user/forensics
    mkdir -p /home/user/solution
    mkdir -p /home/user/legacy_app/src

    # 2. Generate the simulated memory dump
    dd if=/dev/urandom of=/home/user/forensics/memory.dmp bs=1K count=1024
    # Insert the token at a random location
    echo "Some junk data here. SESSION_TOKEN:7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d and more junk" >> /home/user/forensics/memory.dmp
    dd if=/dev/urandom bs=1K count=100 >> /home/user/forensics/memory.dmp

    # 3. Create the legacy app Rust project
    cat << 'EOF' > /home/user/legacy_app/Cargo.toml
[package]
name = "legacy_app"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/legacy_app/src/lib.rs
use std::collections::HashMap;

pub fn get_priority_worker(workers: &HashMap<String, u32>) -> String {
    let mut highest = 0;
    let mut top_worker = String::new();

    for (worker, &score) in workers.iter() {
        // BUG: Tied scores result in non-deterministic selection due to HashMap iteration order.
        if score >= highest {
            highest = score;
            top_worker = worker.clone();
        }
    }

    // Simulate the intermittent panic that happens if a specific tied worker is selected
    if top_worker == "unstable_worker" && highest < 100 {
        panic!("System crash: unstable_worker selected incorrectly during a tie!");
    }

    top_worker
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_intermittent_crash() {
        // Run multiple times to trigger the intermittent HashMap iteration order bug
        for _ in 0..100 {
            let mut workers = HashMap::new();
            workers.insert("alpha_worker".to_string(), 50);
            workers.insert("unstable_worker".to_string(), 50);
            workers.insert("beta_worker".to_string(), 50);

            let res = get_priority_worker(&workers);
            // If the fix is correct, "alpha_worker" should always be selected
            assert_eq!(res, "alpha_worker");
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
