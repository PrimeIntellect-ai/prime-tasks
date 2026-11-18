#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite database
    sqlite3 compliance.db <<'EOF'
CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE hierarchy (manager_id INTEGER, employee_id INTEGER);
CREATE TABLE roles (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE employee_roles (emp_id INTEGER, role_id INTEGER);
CREATE TABLE system_access (role_id INTEGER, system_name TEXT);

INSERT INTO employees VALUES (1, 'Alice');
INSERT INTO employees VALUES (2, 'Bob');
INSERT INTO employees VALUES (3, 'Charlie');
INSERT INTO employees VALUES (4, 'Dave');
INSERT INTO employees VALUES (5, 'Eve');
INSERT INTO employees VALUES (6, 'Frank');

-- Alice manages Bob and Charlie
INSERT INTO hierarchy VALUES (1, 2);
INSERT INTO hierarchy VALUES (1, 3);
-- Bob manages Dave and Eve
INSERT INTO hierarchy VALUES (2, 4);
INSERT INTO hierarchy VALUES (2, 5);
-- Charlie manages Frank
INSERT INTO hierarchy VALUES (3, 6);

INSERT INTO roles VALUES (10, 'General');
INSERT INTO roles VALUES (20, 'Zeus_Operator');

-- Everyone gets General
INSERT INTO employee_roles VALUES (1, 10);
INSERT INTO employee_roles VALUES (2, 10);
INSERT INTO employee_roles VALUES (3, 10);
INSERT INTO employee_roles VALUES (4, 10);
INSERT INTO employee_roles VALUES (5, 10);
INSERT INTO employee_roles VALUES (6, 10);

-- Only Dave gets Zeus_Operator directly
INSERT INTO employee_roles VALUES (4, 20);

INSERT INTO system_access VALUES (10, 'Email');
INSERT INTO system_access VALUES (20, 'Project_Zeus');
EOF

    # Create the buggy Python script
    cat <<'EOF' > audit_access.py
import sqlite3
import csv

def audit():
    conn = sqlite3.connect('compliance.db')
    cursor = conn.cursor()

    # BUG: The recursive part of the CTE does not link 'h.manager_id = s.emp_id'.
    # Instead, it acts as an implicit cross join, linking everyone to everything.
    query = """
    WITH RECURSIVE
    SubordinateGraph(manager_id, emp_id) AS (
        SELECT manager_id, employee_id FROM hierarchy
        UNION ALL
        SELECT s.manager_id, h.employee_id
        FROM SubordinateGraph s, hierarchy h
        -- MISSING WHERE s.emp_id = h.manager_id
    ),
    AllAccess AS (
        -- Direct access
        SELECT er.emp_id, sa.system_name
        FROM employee_roles er
        JOIN system_access sa ON er.role_id = sa.role_id

        UNION

        -- Inherited access
        SELECT sg.manager_id, sa.system_name
        FROM SubordinateGraph sg
        JOIN employee_roles er ON sg.emp_id = er.emp_id
        JOIN system_access sa ON er.role_id = sa.role_id
    )
    SELECT DISTINCT e.name, a.system_name
    FROM AllAccess a
    JOIN employees e ON a.emp_id = e.id
    WHERE a.system_name = 'Project_Zeus'
    ORDER BY e.name;
    """

    # We add a limit to prevent the bad query from running out of memory/hanging forever in some environments
    try:
        cursor.execute(query)
        results = cursor.fetchall()
    except Exception as e:
        print("Query failed:", e)
        return

    with open('zeus_audit.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['employee_name', 'system_name'])
        for row in results:
            writer.writerow(row)

if __name__ == '__main__':
    audit()
EOF

    chmod +x audit_access.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
