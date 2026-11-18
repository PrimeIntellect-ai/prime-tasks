#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    # Seed data
    sqlite3 /home/user/sales.db <<EOF
CREATE TABLE sales (
    id INTEGER PRIMARY KEY,
    region TEXT,
    salesperson TEXT,
    amount REAL,
    sale_date DATE
);

INSERT INTO sales (region, salesperson, amount, sale_date) VALUES 
('North', 'Alice', 2000.00, '2023-01-01'),
('North', 'Alice', 3000.50, '2023-01-15'),
('North', 'Bob', 1500.00, '2023-01-05'),
('North', 'Bob', 1500.00, '2023-02-05'),
('North', 'Charlie', 500.00, '2023-01-10'),
('North', 'Diana', 4000.00, '2023-01-20'),
('South', 'Eve', 6000.00, '2023-01-02'),
('South', 'Frank', 2000.00, '2023-01-03'),
('South', 'Grace', 2500.00, '2023-01-04'),
('South', 'Eve', 1000.00, '2023-01-12');
EOF

    chmod 644 /home/user/sales.db
    chmod -R 777 /home/user
