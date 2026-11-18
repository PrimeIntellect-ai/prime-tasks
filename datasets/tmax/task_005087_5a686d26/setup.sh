#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
node_id,entity_type,region
1,Retail,EU
2,Intermediary,EU
3,Offshore,APAC
4,Retail,EU
5,Intermediary,NA
6,Offshore,APAC
7,Retail,NA
8,Intermediary,NA
9,Offshore,EU
10,Retail,APAC
11,Intermediary,APAC
12,Offshore,APAC
EOF

    cat << 'EOF' > /home/user/edges.csv
source_id,target_id,amount,timestamp
1,2,500.0,100
2,3,1000.0,200
1,5,2000.0,150
5,6,3000.0,250
4,2,800.0,90
4,5,100.0,110
7,8,5000.0,300
8,9,6000.0,400
10,11,400.0,50
11,12,600.0,60
7,5,9000.0,280
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
