#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk tar coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data/region_north/store_12/
    mkdir -p /home/user/raw_data/region_south/store_05/

    cat << 'EOF' > /home/user/raw_data/region_north/store_12/sales_20231001.csv
transaction_id,item_category,quantity,unit_price,discount_percentage
TXN001,Electronics,2,299.99,10
TXN002,Apparel,5,19.50,0
TXN003,Home_Goods,1,150.00,20
EOF

    cat << 'EOF' > /home/user/raw_data/region_south/store_05/sales_20231001.csv
transaction_id,item_category,quantity,unit_price,discount_percentage
TXN004,Electronics,1,899.00,5
TXN005,Apparel,10,15.00,10
TXN006,Groceries,20,3.25,0
EOF

    chown -R user:user /home/user/raw_data
    chmod -R 777 /home/user
