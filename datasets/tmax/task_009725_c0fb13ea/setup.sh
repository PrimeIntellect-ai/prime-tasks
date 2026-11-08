#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/employee_edges.csv
manager,employee,timestamp
Alice,Bob,100
Alice,Charlie,100
Bob,David,100
Bob,Eve,50
Charlie,Eve,120
David,Frank,100
Eve,Grace,130
Zack,Alice,10
Frank,Harry,80
David,Harry,110
Eve,Isabella,140
Isabella,Jack,150
EOF

    chmod -R 777 /home/user
