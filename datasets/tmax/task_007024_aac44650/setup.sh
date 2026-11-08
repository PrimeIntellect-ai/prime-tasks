#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/transactions.csv
transaction_id,age,purchase_amount,review_text,rating
1,25,100.50,"This is a good product.",5
2,30,50.00,"Terrible, not good at all.",2
3,22,120.00,"Excellent purchase!",4
4,40,80.00,"It was okay.",3
5,35,200.00,"Very Good items.",5
6,28,45.00,"Bad experience.",1
7,50,150.00,"good value for money.",4
8,45,90.00,"Nothing special.",3
9,60,300.00,"REALLY GOOD!",5
10,32,60.00,"Broken on arrival.",1
EOF

    chmod -R 777 /home/user
