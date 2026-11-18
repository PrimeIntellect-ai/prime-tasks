#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
id,name,dept
1,Alice,HR
2,Bob,HR
3,Charlie,IT
4,Dave,IT
5,Eve,IT
6,Frank,Sales
7,Grace,Sales
8,Heidi,Sales
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target,weight
1,2,10
1,3,50
2,1,5
3,4,20
4,5,15
5,3,10
6,7,30
7,8,30
8,6,30
1,6,5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
