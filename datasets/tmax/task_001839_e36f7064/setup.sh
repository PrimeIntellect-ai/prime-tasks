#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc sqlite3 libsqlite3-dev
    pip3 install pytest

    mkdir -p /app/logs
    mkdir -p /app/audit_logger/src
    mkdir -p /app/evidence_api/src

    # Create system log
    cat << 'EOF' > /app/logs/system.log
[INFO] System started.
[ALERT] Backdoor installed. Auth hash: 03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4
[INFO] Normal operation resumed.
EOF

    # Create evidence.db
    sqlite3 /app/evidence.db "CREATE TABLE evidence (id INTEGER PRIMARY KEY, data TEXT);"
    sqlite3 /app/evidence.db "INSERT INTO evidence (id, data) VALUES (1, '{\"evidence\": \"found\"}');"
    sqlite3 /app/evidence.db "INSERT INTO evidence (id, data) VALUES (2, '{\"evidence\": \"hidden\"}');"

    # Create audit_logger
    cat << 'EOF' > /app/audit_logger/Cargo.toml
[package]
name = "audit_logger"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > /app/audit_logger/src/main.rs
use std::net::TcpListener;
use std::io::Read;

fn main() {
    let listener = TcpListener::bind("127.0.0.1:9000").unwrap();
    for stream in listener.incoming() {
        if let Ok(mut stream) = stream {
            let mut buf = [0; 1024];
            let _ = stream.read(&mut buf);
        }
    }
}
EOF

    # Create evidence_api
    cat << 'EOF' > /app/evidence_api/Cargo.toml
[package]
name = "evidence_api"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = "0.29.0"
EOF

    cat << 'EOF' > /app/evidence_api/src/main.rs
use rusqlite::Connection;
use std::net::TcpListener;
use std::io::{Read, Write};

fn main() {
    let listener = TcpListener::bind("127.0.0.1:8000").unwrap();
    let conn = Connection::open("/app/evidence.db").unwrap();

    for stream in listener.incoming() {
        if let Ok(mut stream) = stream {
            let mut buffer = [0; 1024];
            if stream.read(&mut buffer).is_ok() {
                let request = String::from_utf8_lossy(&buffer[..]);
                if request.starts_with("GET /record?id=") {
                    let id_param = request.split("GET /record?id=").nth(1).unwrap_or("").split(" ").nth(0).unwrap_or("");

                    let query = format!("SELECT data FROM evidence WHERE id = '{}'", id_param);
                    let mut stmt = conn.prepare(&query).unwrap();

                    let mut rows = stmt.query([]).unwrap();
                    let mut response_body = String::new();
                    while let Ok(Some(row)) = rows.next() {
                        let data: String = row.get(0).unwrap();
                        response_body.push_str(&data);
                    }

                    if response_body.is_empty() {
                        let response = "HTTP/1.1 404 NOT FOUND\r\n\r\n";
                        let _ = stream.write(response.as_bytes());
                    } else {
                        let response = format!("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{}", response_body);
                        let _ = stream.write(response.as_bytes());
                    }
                }
            }
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
