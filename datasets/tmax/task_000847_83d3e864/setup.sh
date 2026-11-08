#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.csv
id,name,department,salary
1,Alice,Exec,200000
2,Bob,Engineering,150000
3,Charlie,Engineering,120000
4,Diana,Engineering,110000
5,Eve,Sales,130000
6,Frank,Sales,90000
7,Grace,Engineering,100000
8,Heidi,Sales,80000
9,Ivan,Exec,150000
EOF

    cat << 'EOF' > /home/user/reporting.csv
emp_id,manager_id
2,1
5,1
3,2
4,2
6,5
7,3
8,6
EOF

    chmod -R 777 /home/user
