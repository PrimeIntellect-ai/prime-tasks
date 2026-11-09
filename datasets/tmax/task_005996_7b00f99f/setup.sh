#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest rdflib pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/employees.csv
emp_id,name,manager_id
E001,Alice CEO,
E002,Bob VP,E001
E003,Charlie Director,E002
E004,Diana Manager,E003
E005,Eve IC,E004
E006,Frank IC,E004
E007,Grace VP,E001
E008,Heidi IC,E007
E009,Ivan IC,E003
EOF

    cat << 'EOF' > /home/user/projects.csv
project_id,project_name,emp_id
P1,Alpha,E005
P2,Beta,E005
P3,Gamma,E006
P4,Delta,E008
P5,Epsilon,E009
P6,Zeta,E002
P7,Eta,E003
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
