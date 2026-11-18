#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/departments.csv
dept_id,dept_name
1,Engineering
2,Sales
3,HR
EOF

    cat << 'EOF' > /home/user/employees.csv
emp_id,name,dept_id,manager_id
101,Alice,1,
102,Bob,1,101
103,Charlie,2,101
104,Diana,1,102
105,Eve,2,103
106,Frank,3,101
107,Grace,1,104
EOF

    cat << 'EOF' > /home/user/generate_summary.sh
#!/bin/bash
sqlite3 -header -csv "" <<SQL
.import --csv /home/user/departments.csv departments
.import --csv /home/user/employees.csv employees

-- BUG: Implicit cross join below
SELECT 
    departments.dept_name, 
    COUNT(employees.emp_id) as employee_count
FROM 
    departments, employees
GROUP BY 
    departments.dept_name;
SQL
EOF

    chmod +x /home/user/generate_summary.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
