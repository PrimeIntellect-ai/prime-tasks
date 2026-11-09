#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
id,title,year
P001,Graph Processing Basics,2020
P002,Advanced SQL,2019
P003,Data Querying Patterns,2018
P004,Recursive CTEs in Practice,2015
P005,Irrelevant Paper,2021
P006,Deep Graph Traversals,2012
P007,Beyond Depth 3,2010
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target
P001,P002
P001,P003
P002,P004
P004,P006
P005,P001
P006,P007
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
