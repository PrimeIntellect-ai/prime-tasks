#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    sqlite3 legacy_system.db <<EOF
CREATE TABLE t1_emp (
    e_id INTEGER PRIMARY KEY,
    e_name TEXT,
    m_id INTEGER,
    d_code TEXT
);

CREATE TABLE t2_dept (
    d_code TEXT PRIMARY KEY,
    d_name TEXT
);

CREATE TABLE t3_txn (
    t_id INTEGER PRIMARY KEY,
    ref_id INTEGER,
    amount INTEGER
);

INSERT INTO t2_dept VALUES ('EXEC', 'Executive'), ('SAL', 'Sales'), ('MKT', 'Marketing'), ('ENG', 'Engineering');

INSERT INTO t1_emp VALUES 
(1, 'Alice', NULL, 'EXEC'),
(2, 'Bob', 1, 'SAL'),
(3, 'Charlie', 2, 'SAL'),
(4, 'Dave', 3, 'SAL'),
(5, 'Eve', 3, 'SAL'),
(6, 'Frank', 1, 'MKT'),
(7, 'Grace', 6, 'MKT'),
(8, 'Heidi', 1, 'ENG');

INSERT INTO t3_txn (ref_id, amount) VALUES 
(2, 100),
(3, 50),
(4, 200),
(4, 50),
(5, 150),
(7, 20);
EOF

    chmod -R 777 /home/user
