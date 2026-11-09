#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo systemd logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Setup Rust project
    mkdir -p /home/user/rust-app/src
    cat << 'EOF' > /home/user/rust-app/Cargo.toml
[package]
name = "main-app"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /home/user/rust-app/src/main.rs
use std::fs::{OpenOptions, File};
use std::io::Write;
use std::thread;
use std::time::Duration;

fn main() {
    // Fails if the log directory hasn't been created by init-env.service
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open("/home/user/logs/app.log")
        .expect("Failed to open log file. Does the directory exist?");

    for _ in 0..10 {
        writeln!(file, "Application log entry.").unwrap();
        thread::sleep(Duration::from_millis(100));
    }
}
EOF

    # Setup systemd user services
    mkdir -p /home/user/.config/systemd/user/

    cat << 'EOF' > /home/user/.config/systemd/user/init-env.service
[Unit]
Description=Initialize Environment Filesystem

[Service]
Type=oneshot
ExecStart=/bin/mkdir -p /home/user/logs
ExecStart=/bin/touch /home/user/logs/tz_info
RemainAfterExit=yes
EOF

    cat << 'EOF' > /home/user/.config/systemd/user/main-app.service
[Unit]
Description=Main Rust Application

[Service]
Type=simple
ExecStart=/home/user/bin/main-app
Restart=on-failure
EOF

    # Setup logrotate conf
    cat << 'EOF' > /home/user/logrotate.conf
/home/user/logs/app.log {
    missingok
    notifempty
    size 1k
    copytruncate
}
EOF

    chmod -R 777 /home/user
