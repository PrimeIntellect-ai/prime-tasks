#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 libsqlite3-dev g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.sql
CREATE TABLE emp_events (
    event_id INTEGER PRIMARY KEY,
    emp_id INTEGER,
    manager_id INTEGER,
    salary REAL,
    dept TEXT,
    event_timestamp DATETIME
);

INSERT INTO emp_events (emp_id, manager_id, salary, dept, event_timestamp) VALUES
(100, 10, 50000, 'Sales', '2022-01-01 10:00:00'),
(101, 10, 52000, 'Sales', '2022-01-05 10:00:00'),
(100, 11, 55000, 'Sales', '2022-06-01 10:00:00'),
(102, 20, 80000, 'Engineering', '2022-02-01 09:00:00'),
(102, 20, 90000, 'Engineering', '2023-01-01 09:00:00'),
(103, 20, 85000, 'Engineering', '2022-03-01 09:00:00'),
(103, -1, 0, 'Engineering', '2023-05-01 09:00:00'),
(104, 20, 82000, 'Engineering', '2023-06-01 09:00:00');
EOF

    sqlite3 hr_data.db < setup_db.sql
    rm setup_db.sql

    chown -R user:user /home/user
    chmod -R 777 /home/user
