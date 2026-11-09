#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.csv
emp_id,name,manager_id
1,Alice,
2,Bob,1
3,Charlie,1
4,David,2
5,Eve,2
6,Frank,3
7,Grace,6
8,Heidi,1
EOF

    cat << 'EOF' > /home/user/projects.csv
emp_id,project_name,hours,cost
1,ProjA,10,1000
2,ProjB,20,2000
3,ProjC,30,3000
4,ProjD,40,4000
5,ProjE,50,5000
6,ProjF,60,6000
7,ProjG,70,7000
8,ProjH,80,8000
4,ProjD2,15,1500
EOF

    chmod -R 777 /home/user
