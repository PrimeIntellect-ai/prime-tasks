#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
id,type,name
n1,Person,Alice
n2,Person,Bob
n3,Person,Charlie
n4,Company,TechCorp
n5,Company,DataInc
n6,Company,FutureAI
n7,Industry,AI
n8,Industry,Finance
n9,Industry,Healthcare
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target,relation
n1,n4,WORKS_FOR
n2,n5,WORKS_FOR
n3,n6,WORKS_FOR
n2,n6,WORKS_FOR
n4,n7,OPERATES_IN
n5,n8,OPERATES_IN
n6,n7,OPERATES_IN
n1,n8,INVESTS_IN
EOF

    chmod -R 777 /home/user
