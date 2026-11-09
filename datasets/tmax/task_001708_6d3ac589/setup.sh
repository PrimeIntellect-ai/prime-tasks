#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/nodes.csv
node_id,name,department
1,Alice,Engineering
2,Bob,Engineering
3,Charlie,Sales
4,Diana,Marketing
5,Eve,Engineering
6,Frank,Sales
7,Grace,HR
EOF

    cat << 'EOF' > /home/user/data/edges.csv
manager_id,employee_id
1,2
1,3
2,5
3,4
4,1
6,7
1,7
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
