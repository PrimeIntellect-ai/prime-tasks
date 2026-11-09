#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 curl build-essential libsqlite3-dev pkg-config
    pip3 install pytest

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust

    mkdir -p /home/user
    cd /home/user

    sqlite3 graph.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, type TEXT, name TEXT);
CREATE TABLE edges (source INTEGER, target INTEGER, weight REAL);
CREATE INDEX idx_edges_target ON edges(target);

INSERT INTO nodes (id, type, name) VALUES 
(1, 'Service', 'AuthService'),
(2, 'Service', 'PaymentService'),
(3, 'Service', 'EmailService'),
(4, 'Database', 'UserDB'),
(5, 'Database', 'TransactionDB'),
(6, 'Queue', 'JobQueue');

INSERT INTO edges (source, target, weight) VALUES 
(1, 4, 10.5),
(2, 5, 20.0),
(1, 5, 5.0),
(3, 6, 8.0),
(2, 6, 12.0),
(4, 1, 16.0),
(5, 2, 10.0),
(6, 3, 5.0);
EOF

    sqlite3 graph.db "PRAGMA writable_schema = ON; UPDATE sqlite_master SET sql = 'CREATE INDEX idx_edges_target ON edges(target)' WHERE name = 'idx_edges_target'; PRAGMA writable_schema = OFF;"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
