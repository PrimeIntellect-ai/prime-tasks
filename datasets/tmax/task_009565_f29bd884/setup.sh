#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang
    pip3 install pytest

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/setup_db.sql
CREATE TABLE services (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);

CREATE TABLE calls (
    source_id INTEGER,
    target_id INTEGER,
    call_count INTEGER,
    latency_ms REAL,
    FOREIGN KEY(source_id) REFERENCES services(id),
    FOREIGN KEY(target_id) REFERENCES services(id)
);

INSERT INTO services (id, name) VALUES 
(1, 'Web'), 
(2, 'Auth'), 
(3, 'Billing'), 
(4, 'Inventory'), 
(5, 'DB');

INSERT INTO calls (source_id, target_id, call_count, latency_ms) VALUES 
(1, 2, 100, 100.0),
(1, 3, 50, 50.0),
(1, 4, 10, 20.0),
(3, 2, 200, 200.0),
(3, 5, 500, 10.0),
(3, 4, 100, 5.0),
(4, 2, 50, 300.0),
(4, 5, 80, 150.0);
EOF

    sqlite3 /home/user/microservices.db < /home/user/setup_db.sql
    rm /home/user/setup_db.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
