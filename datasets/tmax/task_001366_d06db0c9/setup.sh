#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.csv
emp_id,emp_name,manager_id
10,CEO,
20,VP Eng,10
30,VP Sales,10
40,Dev Manager,20
50,Dev 1,40
60,Dev 2,40
70,Sales Lead,30
EOF

    cat << 'EOF' > /home/user/projects.csv
proj_id,emp_id,budget
101,50,5000
102,60,7000
103,40,2000
104,70,3000
105,30,1000
106,10,0
EOF

    chmod -R 777 /home/user
