#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.csv
id,name,region
1,Alice,North
2,Bob,South
3,Charlie,North
4,David,East
5,Eve,South
6,Frank,West
EOF

    cat << 'EOF' > /home/user/data/purchases.csv
user_id,amount,date
1,150.50,2023-10-01
2,20.25,2023-10-02
1,300.00,2023-10-03
3,75.00,2023-10-04
4,500.00,2023-10-05
5,120.50,2023-10-06
6,10.00,2023-10-07
3,25.25,2023-10-08
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
