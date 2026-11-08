#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y sqlite3 libsqlite3-dev gcc

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create the database setup script
    cat << 'EOF' > /home/user/setup_db.sql
CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, department TEXT);
CREATE TABLE communications (sender_id INTEGER, receiver_id INTEGER, message_count INTEGER);

INSERT INTO employees VALUES
(1, 'Alice', 'Engineering'), (2, 'Bob', 'Engineering'),
(3, 'Charlie', 'Marketing'), (4, 'Diana', 'Marketing'),
(5, 'Eve', 'HR'), (6, 'Frank', 'Sales'), (7, 'Grace', 'Sales');

INSERT INTO communications VALUES
(1, 3, 100), -- Eng to Mkt
(2, 4, 150), -- Eng to Mkt (Total Eng->Mkt = 250)
(1, 6, 200), -- Eng to Sales (Total Eng->Sales = 200)
(3, 1, 50),  -- Mkt to Eng
(4, 5, 300), -- Mkt to HR (Total Mkt->HR = 300)
(5, 2, 400), -- HR to Eng
(5, 6, 100), -- HR to Sales
(6, 1, 500), -- Sales to Eng
(7, 3, 600); -- Sales to Mkt
EOF

    # Initialize the database
    sqlite3 /home/user/corp.db < /home/user/setup_db.sql
    rm /home/user/setup_db.sql

    # Set permissions
    chmod -R 777 /home/user
