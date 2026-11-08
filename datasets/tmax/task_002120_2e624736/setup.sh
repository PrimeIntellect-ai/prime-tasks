#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup the repository
    mkdir -p /app/system-daemon
    cd /app/system-daemon
    cargo init --bin

    cat << 'EOF' > src/metrics.rs
pub fn get_metrics() -> String {
    "Metrics OK".to_string()
}
EOF

    cat << 'EOF' > src/main.rs
mod metrics;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;

fn handle_client(mut stream: std::net::TcpStream) {
    let mut buffer = [0; 1024];
    if let Ok(size) = stream.read(&mut buffer) {
        let request = String::from_utf8_lossy(&buffer[..size]);
        if request.starts_with("GET /api/v1/metrics") {
            let body = metrics::get_metrics();
            let response = format!("HTTP/1.1 200 OK\r\n\r\n{}", body);
            stream.write_all(response.as_bytes()).unwrap();
        } else {
            let response = "HTTP/1.1 404 NOT FOUND\r\n\r\nNot Found";
            stream.write_all(response.as_bytes()).unwrap();
        }
    }
}

fn main() {
    let listener = TcpListener::bind("0.0.0.0:8080").unwrap();
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                thread::spawn(move || {
                    handle_client(stream);
                });
            }
            Err(_) => {}
        }
    }
}
EOF

    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"
    git add .
    git commit -m "Initial commit"
    git tag v1.0.0

    # 150 good commits
    for i in $(seq 1 150); do
        echo "// good commit $i" >> src/dummy.rs
        git add src/dummy.rs
        git commit -m "Good commit $i"
    done

    # 1 bad commit
    cat << 'EOF' > src/metrics.rs
pub fn get_metrics() -> String {
    unsafe { std::ptr::null::<u8>().read() };
    "Metrics OK".to_string()
}
EOF
    git add src/metrics.rs
    git commit -m "Update metrics handler"

    # 49 good commits
    for i in $(seq 1 49); do
        echo "// good commit after bad $i" >> src/dummy.rs
        git add src/dummy.rs
        git commit -m "Good commit after bad $i"
    done

    # Ensure we are on main
    git branch -m main || true

    # Make the Rust installation accessible to the user
    chmod -R 777 /root/.cargo || true
    chmod -R 777 /root/.rustup || true

    # Fix permissions
    chmod -R 777 /app/system-daemon
    chmod -R 777 /home/user
