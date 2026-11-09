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
4,David,2,120000
5,Eve,2,110000
6,Frank,4,90000
7,Grace,4,95000
8,Heidi,5,85000
9,Ivan,3,100000
10,Judy,9,80000
EOF

    chmod -R 777 /home/user
