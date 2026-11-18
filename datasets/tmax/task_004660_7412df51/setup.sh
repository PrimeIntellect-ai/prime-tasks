#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.csv
emp_id,emp_name,manager_id
1,Alice,NULL
2,Bob,1
3,Charlie,1
4,David,2
5,Eve,2
6,Frank,3
7,Grace,6
EOF

    cat << 'EOF' > /home/user/sales.csv
emp_id,sale_amount
1,100
2,200
3,150
4,300
5,50
6,400
7,150
EOF

    chmod -R 777 /home/user
