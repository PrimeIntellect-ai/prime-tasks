#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget gnupg

    # Install MongoDB
    wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/mongodb-6.gpg
    echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-6.0.list
    apt-get update && apt-get install -y mongodb-org

    pip3 install pytest pymongo networkx pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/mongo_data

    cat << 'EOF' > /home/user/routes.csv
source,destination,cost
A,B,10.0
A,C,15.0
B,D,12.0
C,D,5.0
D,E,8.0
A,E,40.0
F,G,20.0
G,H,10.0
C,G,25.0
EOF

    cat << 'EOF' > /home/user/orders.csv
order_id,origin,destination
1,A,D
2,A,E
3,B,E
4,F,H
5,A,H
6,C,E
7,D,A
8,C,H
EOF

    chmod -R 777 /home/user
