#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup_db.sql
CREATE TABLE employees (
    id INTEGER PRIMARY KEY,
    name TEXT,
    department_id INTEGER REFERENCES departments(id)
);

CREATE TABLE departments (
    id INTEGER PRIMARY KEY,
    name TEXT,
    manager_id INTEGER REFERENCES employees(id)
);

CREATE TABLE invoices (
    id INTEGER PRIMARY KEY,
    shipment_id INTEGER REFERENCES shipments(id)
);

CREATE TABLE shipments (
    id INTEGER PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id)
);

CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    status TEXT,
    invoice_id INTEGER REFERENCES invoices(id)
);

CREATE TABLE logs (
    id INTEGER PRIMARY KEY,
    message TEXT
);

CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    email TEXT
);

INSERT INTO employees VALUES (1, 'Alice', 1), (2, 'Bob', 1), (3, 'Charlie', 2);
INSERT INTO departments VALUES (1, 'HR', 1), (2, 'Engineering', 3);

INSERT INTO invoices VALUES (1, 1), (2, 2), (3, 3), (4, 4);
INSERT INTO shipments VALUES (1, 1), (2, 1), (3, 2), (4, 2);
INSERT INTO orders VALUES (1, 'Pending', 1), (2, 'Shipped', 2);

INSERT INTO logs VALUES (1, 'Start'), (2, 'Stop');
INSERT INTO users VALUES (1, 'a@a.com');
EOF

sqlite3 /home/user/legacy_system.db < /tmp/setup_db.sql
chown user:user /home/user/legacy_system.db

chmod -R 777 /home/user
