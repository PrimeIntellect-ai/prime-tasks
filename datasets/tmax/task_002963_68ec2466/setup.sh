#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.csv
tx_id,sender,receiver,amount,timestamp
1,A,B,5000,2023-01-01
2,B,C,4000,2023-01-02
3,C,A,3000,2023-01-03
4,X,Y,6000,2023-01-01
5,Y,Z,2000,2023-01-02
6,Z,X,1500,2023-01-03
7,X,Y,1000,2023-01-05
8,Y,Z,5000,2023-01-20
9,M,N,3000,2023-02-01
10,N,O,3000,2023-02-02
11,O,M,3000,2023-02-03
12,M,N,3000,2023-02-15
13,A,X,10000,2023-01-02
14,M,Z,20000,2023-01-05
EOF

    chmod -R 777 /home/user
