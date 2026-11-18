#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 curl build-essential pkg-config libsqlite3-dev
    pip3 install pytest

    # Install Rust globally
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/rust/bin:${PATH}"

    mkdir -p /home/user

    # Setup DB
    sqlite3 /home/user/citations.db <<EOF
CREATE TABLE papers(id INTEGER PRIMARY KEY, title TEXT);
CREATE TABLE citations(source_id INTEGER, target_id INTEGER);
INSERT INTO papers VALUES (10, 'A'), (15, 'B'), (22, 'C'), (42, 'D'), (99, 'E');
-- Path: 10 -> 15 -> 22 -> 42 (Length 3)
INSERT INTO citations VALUES (10, 15);
INSERT INTO citations VALUES (15, 22);
INSERT INTO citations VALUES (22, 42);
INSERT INTO citations VALUES (10, 99);
EOF

    # Setup Rust project
    cargo new /home/user/dataset_manager
    cd /home/user/dataset_manager
    cat << 'EOF' > Cargo.toml
[package]
name = "dataset_manager"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = "0.29.0"
EOF

    cat << 'EOF' > src/main.rs
use rusqlite::{Connection, Result};
use std::env;
use std::thread;
use std::time::Duration;

fn get_db() -> Result<Connection> {
    let conn = Connection::open("/home/user/citations.db")?;
    // TODO: Fix concurrency issues by setting journal_mode to WAL
    Ok(conn)
}

fn shortest_path(from_id: i32, to_id: i32) -> Result<i32> {
    let conn = get_db()?;
    // TODO: Implement recursive CTE to find the shortest path length
    // let mut stmt = conn.prepare("WITH RECURSIVE ...")?;
    // Return the depth

    // Placeholder return:
    Ok(-1)
}

fn run_concurrent_updates() -> Result<()> {
    let t1 = thread::spawn(|| {
        let mut conn = get_db().unwrap();
        let tx = conn.transaction().unwrap();
        tx.execute("UPDATE papers SET title = title || '_updated' WHERE id = 10", []).unwrap();
        thread::sleep(Duration::from_millis(100));
        tx.commit().unwrap();
    });

    let t2 = thread::spawn(|| {
        thread::sleep(Duration::from_millis(50));
        let conn = get_db().unwrap();
        // This read will fail or deadlock if WAL is not enabled
        let _ = conn.query_row("SELECT count(*) FROM papers", [], |row| row.get::<_, i32>(0)).unwrap();
    });

    t1.join().unwrap();
    t2.join().unwrap();
    println!("Concurrency test passed");
    Ok(())
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        return;
    }
    match args[1].as_str() {
        "path" => {
            let from: i32 = args[2].parse().unwrap();
            let to: i32 = args[3].parse().unwrap();
            println!("{}", shortest_path(from, to).unwrap());
        }
        "test-concurrency" => {
            run_concurrent_updates().unwrap();
        }
        _ => {}
    }
}
EOF

    # Pre-fetch dependencies to speed up subsequent runs
    cargo fetch || true

    useradd -m -s /bin/bash user || true

    # Ensure rust environment is available to all users
    echo 'export PATH="/opt/rust/bin:$PATH"' >> /etc/profile.d/rust.sh
    echo 'export PATH="/opt/rust/bin:$PATH"' >> /home/user/.bashrc

    chmod -R 777 /opt/rust
    chmod -R 777 /home/user
