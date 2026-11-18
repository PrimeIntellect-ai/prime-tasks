#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/employees.csv
emp_id,name,manager_id,dept_id
1,Alice,,10
2,Bob,1,10
3,Charlie,1,20
4,Dave,2,10
5,Eve,3,20
EOF

    cat << 'EOF' > /home/user/departments.csv
dept_id,dept_name
10,Engineering
20,Sales
EOF

    cat << 'EOF' > /home/user/generate_report.sh
#!/bin/bash
sqlite3 /home/user/org.db <<SQL
.mode csv
.import /home/user/employees.csv employees
.import /home/user/departments.csv departments

.headers on
.out /home/user/org_chart.csv
-- BUGGY QUERY BELOW
SELECT e.emp_id, e.name, d.dept_name, e.manager_id AS manager_name, e.name AS management_chain
FROM employees e, departments d;
SQL
EOF

    chmod +x /home/user/generate_report.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
