#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import csv

os.makedirs('/home/user', exist_ok=True)

employees_data = [
    ['id', 'name', 'department', 'salary', 'manager_id'],
    [1, 'Alice', 1, 150000, ''],
    [2, 'Bob', 1, 100000, 1],
    [3, 'Charlie', 2, 90000, 1],
    [4, 'David', 2, 80000, 2],
    [5, 'Eve', 3, 120000, 1],
    [6, 'Frank', 3, 60000, 5],
    [7, 'Grace', 4, 45000, 5],
    [8, 'Heidi', 4, 55000, 5],
    [9, 'Ivan', 1, 75000, 2],
    [10, 'Judy', 2, 85000, 2],
    [11, 'Mallory', 3, 52000, 6],
    [12, 'Niaj', 3, 48000, 6],
    [13, 'Oscar', 4, 95000, 8],
    [14, 'Peggy', 4, 62000, 8],
    [15, 'Trent', 1, 110000, 1],
    [16, 'Victor', 2, 71000, 3]
]

departments_data = [
    ['dept_id', 'dept_name', 'parent_dept_id'],
    [1, 'Executive', ''],
    [2, 'Engineering', 1],
    [3, 'Sales', 1],
    [4, 'Marketing', 3]
]

with open('/home/user/employees.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(employees_data)

with open('/home/user/departments.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(departments_data)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
