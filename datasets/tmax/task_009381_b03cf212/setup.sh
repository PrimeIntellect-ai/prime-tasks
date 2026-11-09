#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 jq gawk
pip3 install pytest

mkdir -p /home/user
cd /home/user

cat << 'EOF' > products.csv
product_id,category,product_name
101,Electronics,Laptop
102,Electronics,Smartphone
103,Electronics,Tablet
201,Books,Fiction Book
202,Books,Science Book
203,Books,History Book
301,Clothing,T-Shirt
302,Clothing,Jeans
303,Clothing,Jacket
401,Home,Blender
402,Home,Microwave
EOF

cat << 'EOF' > transactions.csv
tx_id,product_id,tx_date,amount
1,101,2023-01-01,1000.00
2,102,2023-01-02,800.00
3,101,2023-01-03,1000.00
4,103,2023-01-04,300.00
5,201,2023-01-05,15.00
6,202,2023-01-06,25.00
7,203,2023-01-07,20.00
8,201,2023-01-08,15.00
9,301,2023-01-09,20.00
10,302,2023-01-10,50.00
11,303,2023-01-11,100.00
12,302,2023-01-12,50.00
13,401,2023-01-13,40.00
14,402,2023-01-14,90.00
15,102,2023-01-15,800.00
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
