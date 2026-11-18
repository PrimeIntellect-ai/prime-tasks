#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/employees.csv
id,name,manager_id
1,Alice,
2,Bob,1
3,Charlie,1
4,Dave,2
5,Eve,2
6,Frank,3
7,Grace,3
8,Heidi,4
9,Ivan,6
10,Judy,6
EOF

    cat << 'EOF' > /home/user/data/sales.csv
id,amount
1,1000
2,2000
3,1500
4,3000
5,500
6,4000
7,2000
8,2500
9,1000
10,1500
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
