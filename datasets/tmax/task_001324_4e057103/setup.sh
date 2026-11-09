#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gcc libc6-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/sales_dump.csv
TxnID,UserID,UserEmail,UserRegion,ProductID,ProductName,ProductCategory,Price,Quantity,TxnDate
1,101,alice@example.com,EU,501,Laptop,Electronics,1200.00,1,2023-08-15
2,102,bob@example.com,NA,502,Phone,Electronics,800.00,2,2023-08-20
3,103,charlie@example.com,EU,503,Desk,Furniture,300.00,2,2023-07-10
4,101,alice@example.com,EU,504,Chair,Furniture,150.00,4,2023-09-05
5,104,diana@example.com,EU,505,Book,Media,20.00,5,2023-10-12
6,105,evan@example.com,EU,501,Laptop,Electronics,1200.00,2,2023-09-29
7,106,fiona@example.com,AS,503,Desk,Furniture,300.00,1,2023-07-25
8,107,george@example.com,EU,506,Headphones,Electronics,150.00,3,2023-08-01
9,101,alice@example.com,EU,507,Monitor,Electronics,250.00,2,2023-06-15
10,103,charlie@example.com,EU,505,Book,Media,20.00,10,2023-09-15
EOF

    chmod -R 777 /home/user
