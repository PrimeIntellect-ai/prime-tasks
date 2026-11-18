#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        bindfs \
        cargo \
        rustc \
        openssl

    pip3 install pytest aiosmtpd

    # Create directories
    mkdir -p /app/alert-mailer-1.0.0/src
    mkdir -p /home/user/raw_logs
    mkdir -p /home/user/certs
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/corpora/clean
    mkdir -p /home/user/bin

    # Setup alert-mailer
    cat << 'EOF' > /app/alert-mailer-1.0.0/Cargo.toml
[package]
name = "alert-mailer"
version = "1.0.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /app/alert-mailer-1.0.0/src/main.rs
use std::net::TcpStream;

const SMTP_PORT: u16 = 25;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.contains(&"--test".to_string()) {
        match TcpStream::connect(("127.0.0.1", SMTP_PORT)) {
            Ok(_) => {
                println!("Connected successfully");
                std::process::exit(0);
            },
            Err(e) => {
                eprintln!("Failed to connect: {}", e);
                std::process::exit(1);
            }
        }
    }
}
EOF

    # Generate TLS certs
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/certs/key.pem -out /home/user/certs/cert.pem -sha256 -days 365 -nodes -subj "/CN=localhost"

    # Populate corpora
    cat << 'EOF' > /home/user/corpora/evil/evil1.log
192.168.1.1 - GET /index.html?q=<script>alert(1)</script> 200
10.0.0.5 - POST /login?user=admin' UNION SELECT * FROM users-- 403
172.16.0.2 - GET /../../../../etc/passwd 404
EOF

    cat << 'EOF' > /home/user/corpora/clean/clean1.log
192.168.1.1 - GET /index.html 200
10.0.0.5 - POST /login 200
127.0.0.1 - GET /metrics 200
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user
    chmod -R 777 /app
