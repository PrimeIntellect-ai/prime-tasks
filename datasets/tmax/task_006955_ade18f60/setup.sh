#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/employees.csv
emp_id,name,manager_id,salary,department
1,Alice,,200000,Executive
2,Bob,1,150000,Engineering
3,Charlie,1,140000,Sales
4,David,2,120000,Engineering
5,Eve,2,110000,Engineering
6,Frank,3,90000,Sales
7,Grace,3,100000,Sales
8,Heidi,4,80000,Engineering
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
