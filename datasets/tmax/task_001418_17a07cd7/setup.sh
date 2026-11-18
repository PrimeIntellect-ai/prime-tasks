#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3 libsqlite3-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, region TEXT, salary INTEGER, status TEXT);
CREATE INDEX idx_status ON employees(status);

INSERT INTO employees (name, region, salary, status) VALUES 
('Alice', 'NA', 100000, 'ACTIVE'),
('Bob', 'EU', 80000, 'ACTIVE'),
('Charlie', 'NA', 120000, 'INACTIVE'),
('Diana', 'SA', 75000, 'ACTIVE'),
('Evan', 'EU', 90000, 'ACTIVE'),
('Fiona', 'NA', 110000, 'ACTIVE'),
('George', 'SA', 60000, 'INACTIVE');
EOF

    sqlite3 /home/user/backup.db < /tmp/setup_db.sql
    chown user:user /home/user/backup.db

    chmod -R 777 /home/user
