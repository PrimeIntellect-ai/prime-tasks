#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > setup_db.sql
CREATE TABLE orders (
    order_id TEXT PRIMARY KEY,
    customer_id TEXT,
    order_date TEXT,
    status TEXT,
    amount REAL
);
INSERT INTO orders VALUES ('ORD001', 'CUST_A', '2023-10-01T10:00:00Z', 'SHIPPED', 150.50);
INSERT INTO orders VALUES ('ORD002', 'CUST_A', '2023-10-02T11:00:00Z', 'PENDING', 200.00);
INSERT INTO orders VALUES ('ORD003', 'CUST_A', '2023-10-03T12:00:00Z', 'SHIPPED', 99.99);
INSERT INTO orders VALUES ('ORD004', 'CUST_B', '2023-10-01T10:00:00Z', 'SHIPPED', 50.00);
EOF

    sqlite3 /home/user/ecommerce.db < setup_db.sql
    rm setup_db.sql

    chown -R user:user /home/user
    chmod -R 777 /home/user
