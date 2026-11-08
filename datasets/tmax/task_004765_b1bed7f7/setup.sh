#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl nginx rustc cargo
    pip3 install pytest

    # Create app directory
    mkdir -p /app/rusty-slugger-1.2.0/src

    # Create Cargo.toml
    cat << 'EOF' > /app/rusty-slugger-1.2.0/Cargo.toml
[package]
name = "rusty-slugger"
version = "1.2.0"
edition = "2021"

[dependencies]
hyper = "0.14"
tokio = { version = "1", features = ["full"] }
EOF

    # Create perturbed main.rs
    cat << 'EOF' > /app/rusty-slugger-1.2.0/src/main.rs
use std::env;
use std::io::{Read, Write};
use std::net::TcpListener;

fn slugify(input: &str) -> String {
    let mut result = String::new();
    for c in input.chars() {
        if c.is_alphabetic() {
            result.push(c.to_ascii_lowercase());
        } else if c.is_whitespace() || c == '-' {
            if !result.ends_with('-') && !result.is_empty() {
                result.push('-');
            }
        }
    }
    result.trim_end_matches('-').to_string()
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 {
        print!("{}", slugify(&args[1]));
        return;
    }

    env::var("MONITORING_ACTIVE").expect("Missing env var");

    let listener = TcpListener::bind("127.0.0.1:8080").unwrap();
    for stream in listener.incoming() {
        let mut stream = stream.unwrap();
        let mut buffer = [0; 4096];
        if let Ok(bytes_read) = stream.read(&mut buffer) {
            let request = String::from_utf8_lossy(&buffer[..bytes_read]);
            if let Some(body_start) = request.find("\r\n\r\n") {
                let body = request[body_start + 4..].trim_matches(char::from(0));
                let slug = slugify(body);
                let response = format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{}", slug.len(), slug);
                let _ = stream.write_all(response.as_bytes());
            }
        }
    }
}
EOF

    # Create oracle
    mkdir -p /opt/oracle/src
    cat << 'EOF' > /opt/oracle/src/main.rs
use std::env;

fn slugify(input: &str) -> String {
    let mut result = String::new();
    for c in input.chars() {
        if c.is_alphanumeric() {
            result.push(c.to_ascii_lowercase());
        } else if c.is_whitespace() || c == '-' {
            if !result.ends_with('-') && !result.is_empty() {
                result.push('-');
            }
        }
    }
    result.trim_end_matches('-').to_string()
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 {
        print!("{}", slugify(&args[1]));
    }
}
EOF
    rustc /opt/oracle/src/main.rs -o /opt/oracle/rusty-slugger-oracle

    # Setup user and Nginx config
    useradd -m -s /bin/bash user || true
    cat << 'EOF' > /home/user/nginx.conf
worker_processes 1;
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    client_body_temp_path /tmp/client_temp;
    proxy_temp_path /tmp/proxy_temp;
    fastcgi_temp_path /tmp/fastcgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;
    scgi_temp_path /tmp/scgi_temp;
    access_log /tmp/access.log;
    error_log /tmp/error.log;

    server {
        listen 127.0.0.1:9090;
        location /process {
            proxy_pass http://127.0.0.1:8080;
        }
    }
}
EOF

    chmod -R 777 /home/user
