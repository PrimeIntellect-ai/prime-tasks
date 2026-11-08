#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/app/frontend/src /home/user/app/backend/src /home/user/logs /home/user/tools

    cat << 'EOF' > /home/user/app/frontend/src/main.rs
use std::env;

fn main() {
    let timeout_ms: u64 = env::var("API_TIMEOUT_MS")
        .unwrap_or_else(|_| "5000".to_string())
        .parse()
        .expect("Invalid timeout");

    // Simulate frontend logic...
    println!("Timeout set to {} ms", timeout_ms);
}
EOF

    cat << 'EOF' > /home/user/app/backend/src/main.rs
use std::env;

fn main() {
    let port = env::var("SERVER_PORT").unwrap_or_else(|_| "8080".to_string());
    println!("Listening on port {}", port);
}
EOF

    cat << 'EOF' > /home/user/app/.env
SERVER_PORT=8080
API_TIMEOUT_S=30
EOF

    cat << 'EOF' > /home/user/logs/frontend.log
[2023-10-01T10:00:00.000Z] INFO [REQ-001] Starting request
[2023-10-01T10:05:01.000Z] INFO [REQ-008] Received request from client
[2023-10-01T10:05:01.010Z] INFO [REQ-008] Forwarding to backend
[2023-10-01T10:05:01.040Z] ERROR [REQ-008] Timeout exceeded while waiting for backend
[2023-10-01T10:06:00.000Z] INFO [REQ-009] Another request
EOF

    cat << 'EOF' > /home/user/logs/backend.log
[2023-10-01T10:00:00.050Z] INFO [REQ-001] Backend processing
[2023-10-01T10:05:01.015Z] INFO [REQ-008] Backend received payload
[2023-10-01T10:05:01.035Z] INFO [REQ-008] Database query started
[2023-10-01T10:05:01.200Z] INFO [REQ-008] Database query finished
[2023-10-01T10:06:00.020Z] INFO [REQ-009] Backend processing
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
