#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.csv
user_id,name,age,signup_date
1,Alice,25,2023-01-01
2,Bob,,2023-01-02
3,Charlie,150,2023-01-03
4,David,-5,2023-01-04
5,Eve,30,2023-01-05
6,Frank,45,2023-01-06
EOF

    cat << 'EOF' > /home/user/data/purchases.csv
user_id,amount,purchase_date
1,100.50,2023-02-01
1,50.00,2023-02-05
2,200.00,2023-02-02
2,-10.00,2023-02-03
3,500.00,2023-02-01
5,75.25,2023-02-04
6,-50.00,2023-02-06
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
