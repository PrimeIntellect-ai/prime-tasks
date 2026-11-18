#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc sqlite3 curl
    pip3 install pytest

    mkdir -p /app/bom_extractor/src
    mkdir -p /app/data

    cat << 'EOF' > /app/bom_extractor/Cargo.toml
[package]
name = "bom_extractor"
version = "1.0.0"
edition = "2021"

[dependencies]
tokio = { version = "1.28", features = ["full"] }
sqlx = { version = "0.7", features = ["runtime-tokio-rustls", "macros"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /app/bom_extractor/src/main.rs
use sqlx::sqlite::SqlitePool;
use std::env;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: {} <db_path> <part_id>", args[0]);
        std::process::exit(1);
    }
    let db_path = &args[1];
    let part_id = &args[2];

    let pool = SqlitePool::connect(&format!("sqlite://{}", db_path)).await?;

    // Placeholder query
    // The agent needs to implement a recursive CTE here
    let rows = sqlx::query("SELECT 1 as placeholder").fetch_all(&pool).await?;

    println!("[]");
    Ok(())
}
EOF

    sqlite3 /app/data/sample.db <<EOF
CREATE TABLE parts (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE assemblies (parent_id INTEGER, child_id INTEGER, quantity INTEGER);
INSERT INTO parts VALUES (1, 'Car'), (2, 'Wheel'), (3, 'Engine'), (4, 'Tire'), (5, 'Rim');
INSERT INTO assemblies VALUES (1, 2, 4), (1, 3, 1), (2, 4, 1), (2, 5, 1);
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app
    chmod -R 777 /app
    chmod -R 777 /home/user
