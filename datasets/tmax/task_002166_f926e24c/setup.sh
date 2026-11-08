#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
user_id,name
1,Alice
2,Bob
3,Charlie
4,David
5,Eve
EOF

    cat << 'EOF' > /home/user/products.csv
product_id,category
100,Electronics
101,Electronics
102,Books
103,Books
104,Clothing
EOF

    cat << 'EOF' > /home/user/purchases.csv
user_id,product_id
1,100
1,101
2,100
2,101
2,102
3,101
3,103
4,104
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
