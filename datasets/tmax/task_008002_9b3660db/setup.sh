#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest scikit-learn pandas numpy

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.csv
user_id,age,income
1,25,50000
2,30,60000
3,45,80000
4,22,45000
5,35,75000
6,50,90000
7,28,55000
8,40,85000
9,33,65000
10,60,100000
11,27,52000
12,38,78000
13,42,82000
14,24,48000
15,55,95000
EOF

    cat << 'EOF' > /home/user/data/transactions.csv
user_id,spend
1,1000
2,1200
3,1500
4,900
5,1400
6,1800
7,1100
8,1600
9,1300
10,2000
11,1050
12,1450
13,1550
14,950
15,1900
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
