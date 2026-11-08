#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang jq
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/products.csv
product_id,category,name,price
1,Electronics,Laptop,999.99
2,Electronics,Smartphone,599.99
3,Furniture,Desk,199.50
4,Furniture,Chair,85.00
5,Clothing,Jacket,120.00
EOF

    cat << 'EOF' > /home/user/data/regions.csv
region_id,country,city
101,USA,New York
102,USA,Los Angeles
103,Canada,Toronto
104,UK,London
EOF

    cat << 'EOF' > /home/user/data/sales.csv
sale_id,product_id,region_id,amount,timestamp
1001,1,101,999.99,2023-01-01T10:00:00Z
1002,2,102,599.99,2023-01-02T11:00:00Z
1003,3,103,199.50,2023-01-03T12:00:00Z
1004,4,104,85.00,2023-01-04T13:00:00Z
1005,5,101,120.00,2023-01-05T14:00:00Z
1006,1,102,999.99,2023-01-06T15:00:00Z
1007,2,103,599.99,2023-01-07T16:00:00Z
1008,4,101,85.00,2023-01-08T17:00:00Z
1009,5,104,120.00,2023-01-09T18:00:00Z
1010,4,102,40.00,2023-01-10T19:00:00Z
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
