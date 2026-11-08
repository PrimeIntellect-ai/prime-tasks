#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /var/backups
    mkdir -p /app/graph-backup-analyzer/src

    # Generate SQLite database and golden JSON
    cat << 'EOF' > /tmp/gen_db.py
import sqlite3
import json

conn = sqlite3.connect('/var/backups/graph_data.db')
c = conn.cursor()
c.execute('CREATE TABLE nodes (id TEXT, label TEXT, properties TEXT)')
c.execute('CREATE TABLE edges (source_id TEXT, target_id TEXT, relation_type TEXT)')

results = []
for i in range(500):
    c.execute('INSERT INTO nodes VALUES (?, ?, ?)', (f'u{i}', 'User', '{}'))
    c.execute('INSERT INTO nodes VALUES (?, ?, ?)', (f's{i}', 'Service', '{}'))
    c.execute('INSERT INTO nodes VALUES (?, ?, ?)', (f'd{i}', 'Database', '{}'))
    c.execute('INSERT INTO edges VALUES (?, ?, ?)', (f'u{i}', f's{i}', 'owns'))
    c.execute('INSERT INTO edges VALUES (?, ?, ?)', (f's{i}', f'd{i}', 'depends_on'))
    results.append({"user": f"u{i}", "service": f"s{i}", "database": f"d{i}"})

for i in range(500, 5000):
    c.execute('INSERT INTO nodes VALUES (?, ?, ?)', (f'n{i}', 'Other', '{}'))

conn.commit()
conn.close()

with open('/app/golden_validation.json', 'w') as f:
    json.dump(results, f)
EOF
    python3 /tmp/gen_db.py

    # Create Cargo.toml
    cat << 'EOF' > /app/graph-backup-analyzer/Cargo.toml
[package]
name = "graph-backup-analyzer"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = { version = "0.29.0", features = ["bundled"] }
serde_json = "1.0"
EOF

    # Create Rust source with N+1 query bug
    cat << 'EOF' > /app/graph-backup-analyzer/src/main.rs
use rusqlite::{Connection, Result};
use std::fs::File;
use std::io::Write;
use serde_json::json;

fn main() -> Result<()> {
    let conn = Connection::open("/var/backups/graph_data.db")?;
    let mut stmt = conn.prepare("SELECT id, label FROM nodes")?;
    let node_iter = stmt.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;

    let mut nodes = Vec::new();
    for node in node_iter {
        nodes.push(node?);
    }

    let mut edges = Vec::new();
    // N+1 query issue here
    for (id, _) in &nodes {
        let mut edge_stmt = conn.prepare("SELECT source_id, target_id, relation_type FROM edges WHERE source_id = ?")?;
        let edge_iter = edge_stmt.query_map([id], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?, row.get::<_, String>(2)?))
        })?;
        for edge in edge_iter {
            edges.push(edge?);
        }
    }

    let mut results = Vec::new();
    for (u_id, u_label) in &nodes {
        if u_label == "User" {
            for (s_id, t_id, r_type) in &edges {
                if s_id == u_id && r_type == "owns" {
                    for (s_id2, t_id2, r_type2) in &edges {
                        if s_id2 == t_id && r_type2 == "depends_on" {
                            for (db_id, db_label) in &nodes {
                                if db_id == t_id2 && db_label == "Database" {
                                    results.push(json!({
                                        "user": u_id,
                                        "service": t_id,
                                        "database": db_id
                                    }));
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    let mut file = File::create("/home/user/validation.json").unwrap();
    let json_str = serde_json::to_string(&results).unwrap();
    file.write_all(json_str.as_bytes()).unwrap();

    Ok(())
}
EOF

    # Create verification script
    cat << 'EOF' > /app/verify_speed.py
import time
import subprocess
import json
import sys
import os

start = time.time()
env = os.environ.copy()
env["PATH"] = "/root/.cargo/bin:" + env.get("PATH", "")
res = subprocess.run(["cargo", "run", "--release", "--", "--db", "/var/backups/graph_data.db", "--output", "/home/user/validation.json"], cwd="/app/graph-backup-analyzer", env=env)
end = time.time()

if res.returncode != 0:
    print("Execution failed")
    sys.exit(1)

if end - start > 2.0:
    print(f"Too slow: {end - start} seconds")
    sys.exit(1)

with open('/home/user/validation.json') as f:
    out_data = json.load(f)
with open('/app/golden_validation.json') as f:
    golden = json.load(f)

def sort_key(x): return x.get('user', '')
if sorted(out_data, key=sort_key) != sorted(golden, key=sort_key):
    print("JSON output does not match expected")
    sys.exit(1)

print("Success")
EOF

    # Pre-build to download crates and compile dependencies
    cd /app/graph-backup-analyzer && cargo build --release

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
    chmod -R 777 /var/backups
