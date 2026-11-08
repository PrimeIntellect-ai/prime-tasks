#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
id,name,type
1,Alice,Person
2,Bob,Person
3,Charlie,Person
4,Diana,Person
5,Eve,Person
6,Frank,Person
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target,amount,timestamp
1,2,100,1600000000
2,3,200,1600000100
1,4,150,1600000050
4,5,500,1600000200
5,6,600,1600000300
2,6,150,1600000150
3,1,50,1600000400
4,1,100,1600000250
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
