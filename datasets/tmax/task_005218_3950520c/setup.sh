#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/audit.db <<EOF
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);
CREATE TABLE expenses (id INTEGER PRIMARY KEY, emp_id INTEGER, amount REAL, timestamp TEXT);

INSERT INTO employees VALUES (1, 'Alice', NULL);
INSERT INTO employees VALUES (2, 'Bob', 1);
INSERT INTO employees VALUES (3, 'Charlie', 1);
INSERT INTO employees VALUES (4, 'Dave', 2);
INSERT INTO employees VALUES (5, 'Eve', 2);
INSERT INTO employees VALUES (6, 'Frank', 3);
INSERT INTO employees VALUES (7, 'Grace', 3);
INSERT INTO employees VALUES (8, 'Heidi', 2);

-- Bob's team (Manager 1)
INSERT INTO expenses VALUES (1, 2, 5000.0, '2023-01-01');

-- Charlie's team (Manager 1)
INSERT INTO expenses VALUES (2, 3, 15000.0, '2023-01-01');

-- Dave's team (Manager 2)
INSERT INTO expenses VALUES (3, 4, 11000.0, '2023-01-02');

-- Eve's team (Manager 2)
INSERT INTO expenses VALUES (4, 5, 6000.0, '2023-01-03');
INSERT INTO expenses VALUES (5, 5, 8000.0, '2023-01-04'); -- Total 14000

-- Heidi's team (Manager 2)
INSERT INTO expenses VALUES (6, 8, 20000.0, '2023-01-05'); -- Total 20000

-- Frank's team (Manager 3)
INSERT INTO expenses VALUES (7, 6, 12000.0, '2023-01-06');

-- Grace's team (Manager 3)
INSERT INTO expenses VALUES (8, 7, 25000.0, '2023-01-07');
EOF

    chmod -R 777 /home/user
