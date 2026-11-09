#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite DB
    sqlite3 company.db <<EOF
CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE employees (id INTEGER PRIMARY KEY, dept_id INTEGER, name TEXT);
CREATE TABLE sales (id INTEGER PRIMARY KEY, emp_id INTEGER, amount REAL);

INSERT INTO departments VALUES (1, 'Electronics'), (2, 'Clothing'), (3, 'Home');

INSERT INTO employees VALUES (101, 1, 'Alice'), (102, 1, 'Bob'), (103, 1, 'Charlie');
INSERT INTO employees VALUES (201, 2, 'David'), (202, 2, 'Eve');
INSERT INTO employees VALUES (301, 3, 'Frank');

-- Electronics sales
INSERT INTO sales VALUES (1, 101, 500.0), (2, 101, 300.0); -- Alice: 800
INSERT INTO sales VALUES (3, 102, 1000.0); -- Bob: 1000
INSERT INTO sales VALUES (4, 103, 200.0); -- Charlie: 200

-- Clothing sales
INSERT INTO sales VALUES (5, 201, 150.0); -- David: 150
INSERT INTO sales VALUES (6, 202, 400.0), (7, 202, 50.0); -- Eve: 450

-- Home sales
INSERT INTO sales VALUES (8, 301, 900.0); -- Frank: 900
EOF

    cat << 'EOF' > report.sh
#!/bin/bash
# Bad script
sqlite3 /home/user/company.db "SELECT e.name, d.name, SUM(s.amount) FROM employees e, departments d, sales s GROUP BY e.name, d.name;" > out.txt
EOF
    chmod +x report.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
