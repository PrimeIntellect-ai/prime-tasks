#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq sqlite3 gawk
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/graph
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/graph/nodes.csv
id,label,name
1,Company,TechCorp
2,Company,DataWorks
3,Company,DesignHub
4,Technology,PostgreSQL
5,Technology,MongoDB
6,Technology,React
7,Category,Database
8,Category,Frontend
9,Technology,Redis
10,Company,EmptyCo
EOF

    cat << 'EOF' > /home/user/graph/edges.csv
src,dst,relation
1,4,USES
1,6,USES
2,5,USES
2,9,USES
3,6,USES
4,7,BELONGS_TO
5,7,BELONGS_TO
9,7,BELONGS_TO
6,8,BELONGS_TO
EOF

    chmod -R 777 /home/user
