#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo supervisor logrotate
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/supervisor/conf.d
    mkdir -p /home/user/backups
    mkdir -p /home/user/logs
    mkdir -p /home/user/logrotate.d
    mkdir -p /home/user/run/upstream
    mkdir -p /app/socket_resolver/src
    mkdir -p /app/oracle

    # Create dummy wrapper script
    cat << 'EOF' > /home/user/wrapper.sh
#!/bin/bash
/app/socket_resolver/target/release/socket_resolver >> /home/user/logs/resolver.log 2>&1
EOF
    chmod +x /home/user/wrapper.sh

    # Create initial resolver.conf
    cat << 'EOF' > /home/user/supervisor/conf.d/resolver.conf
[program:resolver_daemon]
command=/bin/false
EOF

    # Create Cargo.toml
    cat << 'EOF' > /app/socket_resolver/Cargo.toml
[package]
name = "socket_resolver"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    # Create buggy main.rs
    cat << 'EOF' > /app/socket_resolver/src/main.rs
use std::io::{self, BufRead};

fn main() {
    let stdin = io::stdin();
    let mut line = String::new();
    if stdin.lock().read_line(&mut line).is_ok() {
        let trimmed = line.trim();
        if trimmed.starts_with("upstream://") {
            let rest = &trimmed[11..];
            let parts: Vec<&str> = rest.split('/').collect();
            if parts.len() == 2 {
                println!("/home/user/run/upstream/{}_{}.sock", parts[0], parts[1]);
                return;
            }
        }
    }
    println!("INVALID");
}
EOF

    # Create oracle source and compile it
    cat << 'EOF' > /app/oracle/main.rs
use std::io::{self, BufRead};

fn main() {
    let stdin = io::stdin();
    let mut line = String::new();
    if stdin.lock().read_line(&mut line).is_ok() {
        let trimmed = line.trim_end_matches('\n').trim_end_matches('\r');
        if let Some(rest) = trimmed.strip_prefix("upstream://") {
            let parts: Vec<&str> = rest.splitn(2, '/').collect();
            if parts.len() == 2 {
                let host_port = parts[0];
                let path = parts[1];
                let hp_parts: Vec<&str> = host_port.splitn(2, ':').collect();
                if hp_parts.len() == 2 {
                    let host = hp_parts[0];
                    let port = hp_parts[1];
                    let is_alnum = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric());
                    if is_alnum(host) && is_alnum(port) && is_alnum(path) {
                        println!("/home/user/run/upstream/{}_{}_{}.sock", host, port, path);
                        return;
                    }
                }
            }
        }
    }
    println!("INVALID");
}
EOF
    rustc /app/oracle/main.rs -o /app/oracle/socket_resolver_oracle
    rm /app/oracle/main.rs

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
