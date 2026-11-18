#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task-specific dependencies
    apt-get install -y sqlite3 libsqlite3-dev gcc

    # Create user
    useradd -m -s /bin/bash user || true

    # Create the database and populate it
    sqlite3 /home/user/company.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER, salary REAL);
INSERT INTO employees (id, name, manager_id, salary) VALUES
(1, 'Alice', NULL, 100000.0),
(2, 'Bob', 1, 80000.0),
(3, 'Charlie', 1, 90000.0),
(4, 'Dave', 2, 60000.0),
(5, 'Eve', 2, 65000.0),
(6, 'Frank', 3, 70000.0),
(7, 'Grace', 6, 50000.0);
EOF

    # Set permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
