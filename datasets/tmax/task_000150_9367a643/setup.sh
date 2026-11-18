#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
user_id,name,age
U1001,Alice Smith,34
U1002,Bob Jones,45
U1003,Charlie Brown,28
U1004,Diana Prince,31
U1005,Eve Davis,55
U1006,Frank White,41
U1007,Grace Hall,29
U1008,Harry King,60
U1009,Ivy Lee,22
U1010,Jack Black,38
EOF

    cat << 'EOF' > /home/user/transactions.csv
tx_id,sender_id,receiver_id,amount
T1,U1005,U1002,600.00
T2,U1005,U1003,450.00
T3,U1002,U1007,800.00
T4,U1002,U1004,100.00
T5,U1003,U1008,550.00
T6,U1005,U1009,1200.00
T7,U1009,U1010,750.00
T8,U1009,U1001,400.00
T9,U1007,U1006,900.00
T10,U1005,U1007,510.00
T11,U1007,U1008,600.00
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
