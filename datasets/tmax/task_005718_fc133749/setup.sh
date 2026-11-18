#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/users.csv
user_id,age,signup_days
1,25,100
2,30,200
3,45,50
4,22,300
5,50,10
6,35,150
EOF

    cat << 'EOF' > /home/user/transactions.csv
user_id,total_spend,txn_count
1,150.5,5
2,300.0,12
3,50.0,2
4,500.0,20
5,10.0,1
6,200.0,8
EOF

    chmod -R 777 /home/user
