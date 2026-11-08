#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/event-ingester/src

    cat << 'EOF' > /home/user/event-ingester/Cargo.toml
[package]
name = "event-ingester"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/event-ingester/src/main.rs
use std::sync::{Arc, Mutex};
use std::thread;
use std::env;
use std::time::Duration;

struct Metrics {
    processed: usize,
}

fn main() {
    let batch_size: usize = env::var("BATCH_SIZE")
        .unwrap_or_else(|_| "10".to_string())
        .parse()
        .expect("BATCH_SIZE must be a number");

    // Application initialization logic dependent on batch size
    let _chunk_count = 10000 / batch_size; 

    let metrics = Arc::new(Mutex::new(Metrics { processed: 0 }));
    let mut handles = vec![];

    for i in 0..10000 {
        let metrics_clone = Arc::clone(&metrics);
        handles.push(thread::spawn(move || {
            // Statistical anomaly: Drops every 100th event
            if i % 100 == 0 {
                return;
            }

            // Simulate some I/O or processing
            thread::sleep(Duration::from_micros(10));

            // Concurrency Bug: Logical Race Condition
            let current = metrics_clone.lock().unwrap().processed;
            thread::yield_now(); // Yield to encourage race condition
            metrics_clone.lock().unwrap().processed = current + 1;
        }));
    }

    for h in handles {
        h.join().unwrap();
    }

    let final_count = metrics.lock().unwrap().processed;
    println!("Final processed count: {}", final_count);
}
EOF

    cat << 'EOF' > /home/user/event-ingester/start.sh
#!/bin/bash
export BATCH_SIZE="0"
cargo run --release
EOF

    chmod +x /home/user/event-ingester/start.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
