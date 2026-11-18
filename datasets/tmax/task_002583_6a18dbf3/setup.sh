#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget unzip g++ sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/departments.csv
1,Engineering
2,Sales
3,Marketing
EOF

    cat << 'EOF' > /home/user/data/employees.csv
1,Alice,,
2,Bob,1,1
3,Charlie,2,1
4,David,2,3
5,Eve,2,3
6,Frank,3,1
7,Grace,2,4
EOF

    cat << 'EOF' > /home/user/data/sales.csv
1,4,100
2,4,150
3,5,300
4,3,50
5,7,400
6,6,200
EOF

    chmod -R 777 /home/user
