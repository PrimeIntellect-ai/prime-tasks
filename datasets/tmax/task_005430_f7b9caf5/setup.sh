#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/clients.csv
c_id,full_name,join_date
1,Alice Smith,2023-01-15
2,Bob Jones,2023-02-20
3,Charlie Brown,2023-03-10
4,Diana Prince,2023-04-05
EOF

    cat << 'EOF' > /home/user/data/items.csv
item_code,category,unit_price,description
101,Electronics,500.00,Smartphone
102,Electronics,200.00,Smartwatch
103,Furniture,150.00,Office Chair
104,Electronics,400.00,Tablet
105,Clothing,50.00,Jacket
EOF

    cat << 'EOF' > /home/user/data/purchases.csv
p_id,c_ref,purchase_date
1001,1,2023-05-01
1002,2,2023-05-02
1003,3,2023-05-03
1004,4,2023-05-04
1005,1,2023-05-05
EOF

    cat << 'EOF' > /home/user/data/purchase_lines.csv
line_id,p_ref,item_ref,qty
1,1001,101,2
2,1001,105,1
3,1002,102,1
4,1003,104,3
5,1004,103,4
6,1005,102,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
