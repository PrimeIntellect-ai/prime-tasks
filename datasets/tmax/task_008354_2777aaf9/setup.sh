#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/org_chart.csv
id,name,manager_id
1,Alice,
2,Bob,1
3,Charlie,1
4,Dave,2
5,Eve,2
6,Frank,3
7,Grace,4
8,Heidi,5
9,Ivan,8
EOF

    chmod -R 777 /home/user
