#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/src

    cat << 'EOF' > /home/user/app/Cargo.toml
[package]
name = "leak-service"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.28", features = ["full"] }
lazy_static = "1.4.0"
EOF

    cat << 'EOF' > /home/user/app/src/main.rs
use std::collections::HashMap;
use std::sync::Mutex;
use tokio::time::{sleep, Duration};

lazy_static::lazy_static! {
    static ref CACHE: Mutex<HashMap<u64, String>> = Mutex::new(HashMap::new());
}

pub async fn process_request(id: u64, payload: String, timeout: bool) {
    CACHE.lock().unwrap().insert(id, payload.clone());

    // Simulate some async work
    sleep(Duration::from_millis(5)).await;

    if timeout {
        println!("Request {} timed out", id);
        // BUG: returns early without removing from CACHE
        return;
    }

    // Normal processing completion
    println!("Request {} completed successfully", id);
    CACHE.lock().unwrap().remove(&id);
}

#[tokio::main]
async fn main() {
    println!("Service started");
}
EOF

    cat << 'EOF' > /home/user/app/service.log
INFO: Request 1001 started
INFO: Request 1001 completed successfully
INFO: Request 1002 started
INFO: Request 1002 completed successfully
WARN: Request 1003 timed out - Payload: GHOST_ORPHAN_9921_DATA
INFO: Request 1004 started
INFO: Request 1004 completed successfully
WARN: Request 1005 timed out - Payload: GHOST_ORPHAN_9921_DATA
WARN: Request 1006 timed out - Payload: GHOST_ORPHAN_9921_DATA
WARN: Request 1007 timed out - Payload: GHOST_ORPHAN_9921_DATA
INFO: Request 1008 started
EOF

    cat << 'EOF' > /home/user/app/memory.hexdump
00000000  47 48 4f 53 54 5f 4f 52  50 48 41 4e 5f 39 39 32  |GHOST_ORPHAN_992|
00000010  31 5f 44 41 54 41 00 00  00 00 00 00 00 00 00 00  |1_DATA..........|
00000020  47 48 4f 53 54 5f 4f 52  50 48 41 4e 5f 39 39 32  |GHOST_ORPHAN_992|
00000030  31 5f 44 41 54 41 00 00  00 00 00 00 00 00 00 00  |1_DATA..........|
00000040  47 48 4f 53 54 5f 4f 52  50 48 41 4e 5f 39 39 32  |GHOST_ORPHAN_992|
00000050  31 5f 44 41 54 41 00 00  00 00 00 00 00 00 00 00  |1_DATA..........|
EOF

    chmod -R 777 /home/user
