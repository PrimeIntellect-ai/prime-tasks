#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.csv
emp_id,name,manager_id,salary
1,Alice,,200000
2,Bob,1,150000
3,Charlie,1,160000
4,David,2,100000
5,Eve,2,110000
6,Frank,3,90000
7,Grace,3,105000
8,Heidi,4,80000
9,Ivan,5,85000
10,Judy,5,95000
11,Mallory,7,120000
EOF

    chmod -R 777 /home/user
