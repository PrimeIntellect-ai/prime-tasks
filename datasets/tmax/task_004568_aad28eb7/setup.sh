#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE employees (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    department TEXT NOT NULL,
    manager_id INTEGER,
    FOREIGN KEY(manager_id) REFERENCES employees(id)
);

CREATE TABLE resources (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    sensitivity_level INTEGER NOT NULL
);

CREATE TABLE access_logs (
    id INTEGER PRIMARY KEY,
    employee_id INTEGER NOT NULL,
    resource_id INTEGER NOT NULL,
    timestamp TEXT NOT NULL,
    FOREIGN KEY(employee_id) REFERENCES employees(id),
    FOREIGN KEY(resource_id) REFERENCES resources(id)
);

-- Seed Data
INSERT INTO employees (id, name, department, manager_id) VALUES
(1, 'Alice', 'Executive', NULL),
(2, 'Bob', 'Compliance', 1),
(3, 'Charlie', 'IT', 2),
(4, 'David', 'Engineering', 1),
(5, 'Eve', 'Engineering', 4),
(6, 'Frank', 'Sales', 1),
(7, 'Grace', 'Sales', 6);

INSERT INTO resources (id, name, sensitivity_level) VALUES
(101, 'Cafeteria_Menu', 1),
(102, 'Source_Code', 2),
(103, 'Audit_Report_2023', 3),
(104, 'Customer_PII_DB', 3);

INSERT INTO access_logs (id, employee_id, resource_id, timestamp) VALUES
(1, 3, 103, '2023-10-01T10:00:00Z'),
(2, 5, 103, '2023-10-01T11:00:00Z'),
(3, 2, 104, '2023-10-01T12:00:00Z'),
(4, 5, 101, '2023-10-01T13:00:00Z'),
(5, 4, 104, '2023-10-01T14:00:00Z'),
(6, 7, 102, '2023-10-01T15:00:00Z');
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
