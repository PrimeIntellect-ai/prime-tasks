#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 curl build-essential pkg-config libsqlite3-dev
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/cargo/bin:$PATH"

    # Create the SQLite DB
    mkdir -p /home/user
    sqlite3 /home/user/metrics.db <<EOF
CREATE TABLE devices (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE measurements (
    id INTEGER PRIMARY KEY,
    device_id INTEGER,
    timestamp DATETIME,
    reading REAL,
    FOREIGN KEY(device_id) REFERENCES devices(id)
);

CREATE INDEX idx_measurements_ts ON measurements(timestamp);

INSERT INTO devices (id, name) VALUES (1, 'Sensor-Alpha'), (2, 'Sensor-Beta');

INSERT INTO measurements (device_id, timestamp, reading) VALUES
(1, '2023-10-01 10:00:00', 40.0),
(1, '2023-10-01 10:05:00', 50.0),
(1, '2023-10-01 10:10:00', 60.0),
(1, '2023-10-01 10:15:00', 45.0),
(1, '2023-10-01 10:20:00', 55.0),
(1, '2023-10-01 10:25:00', 70.0),
(1, '2023-10-01 10:30:00', 30.0),
(1, '2023-10-01 10:35:00', 48.0),
(1, '2023-10-01 10:40:00', 80.0),
(1, '2023-10-01 10:45:00', 90.0),
(2, '2023-10-01 10:00:00', 20.0),
(2, '2023-10-01 10:05:00', 80.0),
(2, '2023-10-01 10:10:00', 85.0),
(2, '2023-10-01 10:15:00', 90.0),
(2, '2023-10-01 10:20:00', 95.0),
(2, '2023-10-01 10:25:00', 40.0),
(2, '2023-10-01 10:30:00', 60.0),
(2, '2023-10-01 10:35:00', 65.0),
(2, '2023-10-01 10:40:00', 70.0),
(2, '2023-10-01 10:45:00', 50.0);
EOF

    # Setup the Rust project
    cd /home/user
    cargo new metrics_processor
    cd metrics_processor
    cat << 'EOF' > Cargo.toml
[package]
name = "metrics_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
rusqlite = "0.29.0"
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /opt/cargo
    chmod -R 777 /opt/rust
