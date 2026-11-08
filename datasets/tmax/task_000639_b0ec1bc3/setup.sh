#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.csv
user_id,name
1,Alice
2,Bob
3,Charlie
4,Dave
5,Eve
6,Frank
7,Grace
8,Heidi
9,Ivan
10,Judy
EOF

    cat << 'EOF' > /home/user/data/products.csv
product_id,category
101,Electronics
102,Electronics
103,Books
104,Books
105,Clothing
EOF

    cat << 'EOF' > /home/user/data/orders.csv
order_id,user_id,order_date
1001,1,2023-10-01
1002,2,2023-10-03
1003,3,2023-10-05
1004,4,2023-10-08
1005,5,2023-10-10
1006,6,2023-10-01
1007,7,2023-10-02
1008,8,2023-10-09
1009,9,2023-10-10
1010,10,2023-10-15
1011,1,2023-10-16
EOF

    cat << 'EOF' > /home/user/data/order_items.csv
order_id,product_id
1001,101
1002,102
1003,101
1004,102
1005,102
1006,103
1007,104
1008,103
1009,104
1010,104
1011,104
EOF

    chmod -R 777 /home/user
