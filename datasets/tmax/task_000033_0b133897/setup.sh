#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.sql
CREATE TABLE personnel (
    emp_id INTEGER PRIMARY KEY,
    full_name TEXT NOT NULL,
    manager_id INTEGER,
    clearance_level INTEGER NOT NULL
);

CREATE TABLE it_systems (
    system_id INTEGER PRIMARY KEY,
    sys_name TEXT NOT NULL,
    required_clearance INTEGER NOT NULL
);

CREATE TABLE access_events (
    event_id INTEGER PRIMARY KEY,
    emp_id INTEGER,
    system_id INTEGER,
    access_date TEXT NOT NULL
);

-- Insert Data
INSERT INTO personnel VALUES
(1, 'Alice Director', NULL, 5),
(2, 'Bob Manager', 1, 4),
(3, 'Charlie Lead', 2, 3),
(4, 'Dave Worker', 3, 2),
(5, 'Eve Intern', 3, 1),
(6, 'Frank Rogue', 2, 2);

INSERT INTO it_systems VALUES
(101, 'PublicWeb', 1),
(102, 'DevServer', 2),
(103, 'FinanceDB', 4),
(104, 'CoreInfra', 5);

INSERT INTO access_events VALUES
(1001, 1, 104, '2023-10-01'),
(1002, 2, 103, '2023-10-02'),
(1003, 3, 103, '2023-10-03'),
(1004, 4, 102, '2023-10-04'),
(1005, 5, 102, '2023-10-05'),
(1006, 6, 104, '2023-10-06'),
(1007, 4, 104, '2023-10-07');
EOF

    sqlite3 compliance.db < setup_db.sql
    rm setup_db.sql

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
