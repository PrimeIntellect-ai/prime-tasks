#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 gcc libc6-dev libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE employees (
    emp_id INTEGER PRIMARY KEY,
    manager_id INTEGER,
    name TEXT
);

CREATE TABLE access_logs (
    emp_id INTEGER,
    resource_id TEXT,
    access_count INTEGER
);

INSERT INTO employees (emp_id, manager_id, name) VALUES
(1, NULL, 'Alice'),
(2, 1, 'Bob'),
(3, 1, 'Charlie'),
(4, 2, 'Dave'),
(5, 3, 'Eve');

INSERT INTO access_logs (emp_id, resource_id, access_count) VALUES
(1, 'RES_A', 15),
(2, 'RES_A', 7),
(2, 'RES_B', 12),
(1, 'RES_B', 3),
(3, 'RES_C', 5),
(1, 'RES_C', 2),
(4, 'RES_A', 1),
(4, 'RES_B', 8),
(2, 'RES_B', 4),
(5, 'RES_D', 10),
(3, 'RES_D', 4);
EOF

    chmod -R 777 /home/user
