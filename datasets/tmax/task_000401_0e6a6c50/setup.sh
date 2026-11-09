#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang-go
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/tracing.db <<EOF
CREATE TABLE services (
    id INTEGER PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE calls (
    caller_id INTEGER,
    callee_id INTEGER,
    latency_ms INTEGER,
    FOREIGN KEY(caller_id) REFERENCES services(id),
    FOREIGN KEY(callee_id) REFERENCES services(id)
);

INSERT INTO services (id, name) VALUES 
(1, 'API-Gateway'),
(2, 'Auth-Service'),
(3, 'User-Profile'),
(4, 'Billing'),
(5, 'Payment-Gateway'),
(6, 'Email-Service');

-- Graph edges
INSERT INTO calls (caller_id, callee_id, latency_ms) VALUES
(1, 2, 20),
(1, 3, 50),
(2, 3, 10),
(3, 4, 40),
(4, 5, 100),
(3, 6, 15);
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
