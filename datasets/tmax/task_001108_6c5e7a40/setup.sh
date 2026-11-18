#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.csv
id,name,manager_id,salary,dept_id
1,Alice,,100000,10
2,Bob,1,80000,20
3,Charlie,1,85000,10
4,Dave,2,60000,20
5,Eve,2,65000,30
6,Frank,4,50000,20
7,Grace,5,55000,30
EOF

    cat << 'EOF' > /home/user/departments.csv
dept_id,dept_name,budget_modifier
10,Exec,1.0
20,Sales,1.1
30,Engineering,1.2
EOF

    chmod -R 777 /home/user
