#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 curl build-essential libsqlite3-dev pkg-config
    pip3 install pytest

    # Install Rust globally
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust

    useradd -m -s /bin/bash user || true

    # Setup Database
    sqlite3 /home/user/company.db <<EOF
CREATE TABLE employees (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    manager_id INTEGER
);

INSERT INTO employees (id, name, manager_id) VALUES (1, 'Alice', NULL);
INSERT INTO employees (id, name, manager_id) VALUES (2, 'Bob', 1);
INSERT INTO employees (id, name, manager_id) VALUES (3, 'Charlie', 1);
INSERT INTO employees (id, name, manager_id) VALUES (4, 'David', 2);
INSERT INTO employees (id, name, manager_id) VALUES (5, 'Eve', 2);
INSERT INTO employees (id, name, manager_id) VALUES (6, 'Frank', 3);
INSERT INTO employees (id, name, manager_id) VALUES (7, 'Grace', 4);
INSERT INTO employees (id, name, manager_id) VALUES (8, 'Heidi', 5);
INSERT INTO employees (id, name, manager_id) VALUES (9, 'Ivan', 5);
EOF

    chmod -R 777 /home/user
