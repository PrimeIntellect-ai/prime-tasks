#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employees.csv
emp_id,name,salary,manager_id
EMP-001,Alice CEO,300000,
EMP-002,Bob VP,200000,EMP-001
EMP-003,Charlie VP,200000,EMP-001
EMP-004,David Dir,150000,EMP-002
EMP-005,Eve Dir,150000,EMP-003
EMP-006,Frank Mgr,110000,EMP-004
EMP-007,Grace Dev,90000,EMP-006
EMP-008,Heidi Dev,90000,EMP-006
EMP-009,Ivan Mgr,110000,EMP-005
EMP-010,Judy Dev,90000,EMP-009
EMP-011,Mallory Dev,90000,EMP-009
EMP-012,Niaj Intern,50000,EMP-011
EOF

    chmod -R 777 /home/user
