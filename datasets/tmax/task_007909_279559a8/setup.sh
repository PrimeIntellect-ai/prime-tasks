#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc g++ sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/employees.csv
id,name,manager_id,department
1,Alice,,Executive
2,Bob,1,Engineering
3,Charlie,1,Sales
4,David,2,Engineering
5,Eve,2,Engineering
6,Frank,3,Sales
7,Grace,3,Sales
8,Heidi,3,Sales
EOF

    cat << 'EOF' > /home/user/sales.csv
employee_id,amount,date
2,100,2023-01-01
4,150,2023-01-02
4,50,2023-01-03
5,200,2023-01-04
6,300,2023-01-05
7,250,2023-01-06
7,100,2023-01-07
8,500,2023-01-08
1,1000,2023-01-09
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
