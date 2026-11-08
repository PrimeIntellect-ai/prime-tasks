#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/employees.csv
id,department,salary
1,Engineering,100000
2,Engineering,90000
3,Engineering,80000
4,HR,70000
5,HR,60000
6,Engineering,85000
7,Sales,120000
8,Sales,50000
9,Sales,50000
EOF

cat << 'EOF' > /home/user/hierarchy.csv
manager_id,employee_id
1,2
1,3
2,6
4,5
7,8
7,9
EOF

chmod -R 777 /home/user
