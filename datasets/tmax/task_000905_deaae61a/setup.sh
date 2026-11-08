#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/audit_system.db <<EOF
CREATE TABLE staff (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    clearance_doc TEXT NOT NULL
);

CREATE TABLE restricted_access_logs (
    log_id INTEGER PRIMARY KEY,
    staff_id INTEGER,
    project_accessed TEXT NOT NULL,
    FOREIGN KEY(staff_id) REFERENCES staff(id)
);

INSERT INTO staff (id, name, clearance_doc) VALUES 
(1, 'Alice Smith', '{"level": 5, "projects": ["Apollo", "Zeus"]}'),
(2, 'Bob Jones', '{"level": 2, "projects": ["Hermes"]}'),
(3, 'Charlie Brown', '{"level": 4, "projects": ["Apollo", "Hermes", "Ares"]}');

INSERT INTO restricted_access_logs (log_id, staff_id, project_accessed) VALUES
(101, 1, 'Apollo'),
(102, 1, 'Zeus'),
(103, 2, 'Apollo'), 
(104, 2, 'Hermes'),
(105, 3, 'Zeus'),
(106, 3, 'Ares');
EOF

    chmod -R 777 /home/user
