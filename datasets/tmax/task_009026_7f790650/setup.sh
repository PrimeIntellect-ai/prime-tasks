#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cargo rustc
    pip3 install pytest

    mkdir -p /home/user

    # Create SQLite DB
    sqlite3 /home/user/data.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE employee_projects (emp_id INTEGER, proj_id INTEGER);

INSERT INTO employees VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie');
INSERT INTO projects VALUES (10, 'Alpha'), (20, 'Beta');
INSERT INTO employee_projects VALUES (1, 10), (2, 10), (2, 20), (3, 20);
EOF

    # Create Rust project
    mkdir -p /home/user/graph_etl/src
    cat << 'EOF' > /home/user/graph_etl/Cargo.toml
[package]
name = "graph_etl"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = "0.29.0"
EOF

    cat << 'EOF' > /home/user/graph_etl/src/main.rs
use rusqlite::{Connection, Result};
use std::fs::File;
use std::io::Write;

fn main() -> Result<()> {
    let conn = Connection::open("/home/user/data.db")?;

    // BUG: Implicit cross join
    let mut stmt = conn.prepare("SELECT e.name, p.name FROM employees e, projects p")?;

    let edges = stmt.query_map([], |row| {
        let e_name: String = row.get(0)?;
        let p_name: String = row.get(1)?;
        Ok(format!("{},{}", e_name, p_name))
    })?;

    let mut file = File::create("/home/user/output_edges.csv").unwrap();
    for edge in edges {
        writeln!(file, "{}", edge.unwrap()).unwrap();
    }

    Ok(())
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
