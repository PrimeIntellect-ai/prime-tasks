#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 curl build-essential jq
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/cargo/bin:${PATH}"
    chmod -R 777 /opt/rust /opt/cargo

    useradd -m -s /bin/bash user || true

    # Create the SQLite database and seed it with exactly 8 rows
    sqlite3 /home/user/source.db <<EOF
CREATE TABLE events (id INTEGER PRIMARY KEY, source_node INTEGER, target_node INTEGER, event_time DATETIME, action TEXT);

-- Edge 1->2: ADD, REMOVE, ADD (Final: ADD)
INSERT INTO events (source_node, target_node, event_time, action) VALUES (1, 2, '2023-01-01 10:00:00', 'ADD');
INSERT INTO events (source_node, target_node, event_time, action) VALUES (1, 2, '2023-01-02 10:00:00', 'REMOVE');
INSERT INTO events (source_node, target_node, event_time, action) VALUES (1, 2, '2023-01-03 10:00:00', 'ADD');

-- Edge 1->3: ADD, REMOVE (Final: REMOVE)
INSERT INTO events (source_node, target_node, event_time, action) VALUES (1, 3, '2023-01-01 10:00:00', 'ADD');
INSERT INTO events (source_node, target_node, event_time, action) VALUES (1, 3, '2023-01-02 10:00:00', 'REMOVE');

-- Edge 2->4: ADD (Final: ADD)
INSERT INTO events (source_node, target_node, event_time, action) VALUES (2, 4, '2023-01-01 11:00:00', 'ADD');

-- Edge 2->5: ADD, ADD (Final: ADD)
INSERT INTO events (source_node, target_node, event_time, action) VALUES (2, 5, '2023-01-01 11:00:00', 'ADD');
INSERT INTO events (source_node, target_node, event_time, action) VALUES (2, 5, '2023-01-02 11:00:00', 'ADD');

CREATE INDEX idx_corrupt_source ON events(source_node);
EOF

    chmod -R 777 /home/user
