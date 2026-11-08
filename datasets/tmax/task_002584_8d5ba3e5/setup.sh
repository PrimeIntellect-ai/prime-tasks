#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/employees.csv
emp_id,manager_id,salary,department
1,NULL,100000,Sales
2,1,80000,Sales
3,1,75000,Sales
4,2,60000,Sales
5,NULL,120000,Engineering
6,5,90000,Engineering
7,5,95000,Engineering
8,6,70000,Engineering
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
