#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/employees.csv
id,name,department
1,Alice,Engineering
2,Bob,Engineering
3,Charlie,Sales
4,Diana,Sales
5,Eve,Marketing
6,Frank,Marketing
7,Grace,Engineering
EOF

    cat << 'EOF' > /home/user/collaborations.csv
emp_id_1,emp_id_2
1,3
1,4
3,4
2,3
3,5
4,6
6,7
1,7
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
