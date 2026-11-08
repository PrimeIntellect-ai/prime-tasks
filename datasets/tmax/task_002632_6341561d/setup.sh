#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/customers.csv
user_id,first_name,last_name,email
1,Alice,Smith,alice@example.com
2,Bob,Jones,invalid_email
3,Charlie,Brown,charlie@domain.com
4,Diana,Prince,diana@hero.com
EOF

    cat << 'EOF' > /home/user/data/transactions.csv
tx_id,user_id,amount
t1,1,10.0
t2,1,12.0
t3,1,100.0
t4,2,50.0
t5,3,5.0
t6,3,-10.0
t7,3,6.0
t8,3,7.0
t9,4,20.0
t10,4,21.0
t11,4,22.0
EOF

    chmod -R 777 /home/user
