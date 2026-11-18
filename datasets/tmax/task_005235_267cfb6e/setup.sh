#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/products.csv
product_id,category,price,is_active
P001,Electronics,150.00,true
P002,Books,15.99,true
P003,Electronics,250.00,false
P004,Home,120.50,true
P005,Toys,45.00,true
EOF

    cat << 'EOF' > /home/user/transactions.csv
tx_id,product_id,user_id,amount,timestamp
T1001,P001,U99,150.00,2023-10-01T10:00:00Z
T1002,P002,U23,15.99,2023-10-01T10:15:00Z
T1003,P003,U99,250.00,2023-10-01T10:30:00Z
T1004,P004,U45,120.50,2023-10-01T11:00:00Z
T1005,P001,U12,100.00,2023-10-01T11:30:00Z
T1006,P004,U88,130.00,2023-10-01T12:00:00Z
EOF

    chmod -R 777 /home/user
