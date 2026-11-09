#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 curl build-essential pkg-config libsqlite3-dev
    pip3 install pytest

    # Install Rust globally
    export RUSTUP_HOME=/usr/local/rustup
    export CARGO_HOME=/usr/local/cargo
    export PATH=/usr/local/cargo/bin:$PATH
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /usr/local/rustup /usr/local/cargo

    # Setup directories
    mkdir -p /home/user/citation_processor/src

    # Create Cargo.toml
    cat << 'EOF' > /home/user/citation_processor/Cargo.toml
[package]
name = "citation_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = { version = "0.29.0", features = ["bundled"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    # Create main.rs
    cat << 'EOF' > /home/user/citation_processor/src/main.rs
fn main() {
    println!("Please implement me.");
}
EOF

    # Create the SQLite database
    sqlite3 /home/user/dataset.db << 'EOF'
CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT, year INTEGER, domain TEXT);
CREATE TABLE citations (source_id INTEGER, target_id INTEGER);

INSERT INTO papers (id, title, year, domain) VALUES
(1, 'Root Paper', 2020, 'AI'),
(2, 'Sub Paper A', 2019, 'AI'),
(3, 'Sub Paper B', 2018, 'Systems'),
(4, 'Deep Paper C', 2015, 'Systems'),
(5, 'Deep Paper D', 2017, 'AI'),
(6, 'Outside Paper 1', 2021, 'AI'),
(7, 'Outside Paper 2', 2021, 'Systems'),
(8, 'Outside Paper 3', 2022, 'Theory');

-- Graph starting from 1: 1 cites 2 and 3. 2 cites 4. 3 cites 4 and 5.
INSERT INTO citations (source_id, target_id) VALUES
(1, 2),
(1, 3),
(2, 4),
(3, 4),
(3, 5);

-- Outside citations to affect totals
INSERT INTO citations (source_id, target_id) VALUES
(6, 4),
(7, 5),
(8, 2),
(6, 2),
(7, 2);
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
