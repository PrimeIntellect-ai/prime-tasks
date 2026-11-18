#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data /home/user/output

    cat << 'EOF' > /home/user/data/users.csv
user_id,name
1,Alice
2,Bob
3,Charlie
EOF

    cat << 'EOF' > /home/user/data/orders.csv
order_id,user_id,order_date,status
101,1,2023-01-15,completed
102,1,2023-02-10,pending
103,2,2023-01-20,completed
104,3,2023-03-05,completed
EOF

    cat << 'EOF' > /home/user/data/order_items.csv
item_id,order_id,product_name,price
501,101,Widget A,25.50
502,101,Gadget B,15.00
503,103,Widget C,40.00
504,103,Widget A,25.50
505,104,Tool D,10.00
EOF

    chmod -R 777 /home/user
