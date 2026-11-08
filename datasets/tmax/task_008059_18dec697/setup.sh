#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/billing-service/src
    cd /home/user/billing-service
    cargo init --lib

    cat << 'EOF' > /home/user/billing-service/src/calculator.rs
use std::fs::OpenOptions;
use std::io::Write;

pub fn calculate_cost(base: u64, multiplier: u64, discount: u64) -> u64 {
    // Faulty logic that panics on underflow
    (base * multiplier) - discount
}
EOF

    cat << 'EOF' > /home/user/billing-service/src/lib.rs
pub mod calculator;
EOF

    dd if=/dev/urandom of=/home/user/crash.dmp bs=1K count=1024 2>/dev/null
    echo "Some random memory garbage before the string... FATAL_ERROR_FOR_TRACE_ID: TXN-7734-ALPHA-09 ...and some garbage after." >> /home/user/crash.dmp
    dd if=/dev/urandom bs=1K count=512 >> /home/user/crash.dmp 2>/dev/null

    chmod -R 777 /home/user
