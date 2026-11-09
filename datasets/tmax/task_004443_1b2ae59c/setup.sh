#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 jq
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/products.csv
product_id,category,name
1,Electronics,Laptop
2,Electronics,Smartphone
3,Electronics,Tablet
4,Electronics,Monitor
5,Clothing,Shirt
6,Clothing,Pants
7,Clothing,Jacket
8,Clothing,Hat
9,Clothing,Socks
10,Clothing,Shoes
EOF

    cat << 'EOF' > /home/user/data/sales.csv
transaction_id,date,product_id,quantity,price
1,2023-01-01,1,2,1000
2,2023-01-01,2,5,500
3,2023-01-02,1,1,1000
4,2023-01-02,3,10,300
5,2023-01-03,4,4,200
6,2023-01-03,2,2,500
7,2023-01-04,1,1,1000
8,2023-01-05,5,10,20
9,2023-01-05,6,5,50
10,2023-01-06,7,2,100
11,2023-01-06,8,20,10
12,2023-01-07,9,30,5
13,2023-01-07,10,5,60
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
