#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.csv
id,name,department,budget
1,Alice,Engineering,100
2,Bob,Engineering,50
3,Charlie,Engineering,60
4,David,HR,80
5,Eve,HR,40
6,Frank,Marketing,120
7,Grace,Marketing,30
8,Heidi,Engineering,20
9,Ivan,Engineering,10
10,Judy,Marketing,50
11,Mallory,Marketing,70
12,Oscar,HR,90
13,Peggy,Engineering,15
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target
1,2
1,3
2,8
3,9
4,5
6,7
6,10
10,11
11,12
8,13
EOF

    chmod -R 777 /home/user
