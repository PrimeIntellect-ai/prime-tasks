#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/categories.csv
category_id,category_name,parent_category_id
1,All,
2,Electronics,1
3,Computers,2
4,Laptops,3
5,Phones,2
6,Clothing,1
EOF

    cat << 'EOF' > /home/user/data/products.csv
product_id,category_id,product_name
101,4,MacBook Pro
102,5,iPhone 14
103,6,T-Shirt
104,3,Desktop PC
EOF

    cat << 'EOF' > /home/user/data/sales.csv
sale_id,product_id,sale_date,quantity,price
1,101,2023-09-28,1,2000
2,101,2023-09-29,1,2000
3,101,2023-10-01,1,2000
4,101,2023-10-02,2,2000
5,101,2023-10-05,1,2000
6,102,2023-10-01,5,1000
7,103,2023-10-01,10,20
8,104,2023-10-15,1,1500
9,101,2023-10-20,1,2000
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
