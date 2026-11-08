#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    # Clone sqlglot
    mkdir -p /app/vendor
    git clone --depth 1 --branch v20.0.0 https://github.com/tobymao/sqlglot.git /app/vendor/sqlglot

    # Inject perturbation
    sed -i '1i import tyops' /app/vendor/sqlglot/sqlglot/__init__.py

    # Create corpora
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Clean queries
    cat << 'EOF' > /app/corpus/clean/clean1.sql
SELECT * FROM departments;
EOF
    cat << 'EOF' > /app/corpus/clean/clean2.sql
SELECT id, name FROM employees WHERE active = 1;
EOF
    cat << 'EOF' > /app/corpus/clean/clean3.sql
WITH dept_counts AS (SELECT dept_id, COUNT(*) as c FROM employees GROUP BY dept_id) SELECT * FROM dept_counts;
EOF
    cat << 'EOF' > /app/corpus/clean/clean4.sql
SELECT a.name, b.name FROM employees a JOIN departments b ON a.dept_id = b.id;
EOF
    cat << 'EOF' > /app/corpus/clean/clean5.sql
WITH RECURSIVE org_chart AS (SELECT id, manager_id FROM employees WHERE manager_id IS NULL UNION ALL SELECT e.id, e.manager_id FROM employees e JOIN org_chart o ON e.manager_id = o.id) SELECT * FROM org_chart;
EOF

    # Evil queries
    cat << 'EOF' > /app/corpus/evil/evil1.sql
UPDATE departments SET name = 'Hacked';
EOF
    cat << 'EOF' > /app/corpus/evil/evil2.sql
SELECT * FROM employee_salaries;
EOF
    cat << 'EOF' > /app/corpus/evil/evil3.sql
WITH secret AS (SELECT * FROM system_credentials) SELECT * FROM secret;
EOF
    cat << 'EOF' > /app/corpus/evil/evil4.sql
SELECT e.name, s.amount FROM employees e JOIN employee_salaries s ON e.id = s.emp_id;
EOF
    cat << 'EOF' > /app/corpus/evil/evil5.sql
DROP TABLE employees;
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
