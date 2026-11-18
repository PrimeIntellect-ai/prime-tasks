#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils grep sed
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/transactions.csv
tx_id,src_account,dst_account,amount,timestamp
1,ACC_001,ACC_002,500,1620000000
2,ACC_002,ACC_003,300,1620000010
3,ACC_003,ACC_004,100,1620000020
4,ACC_004,ACC_005,100,1620000030
5,ACC_010,ACC_011,900,1620000040
6,ACC_011,ACC_012,900,1620000050
7,ACC_012,ACC_010,900,1620000060
8,ACC_888,ACC_100,500,1620000070
9,ACC_100,ACC_200,500,1620000080
10,ACC_200,ACC_300,500,1620000090
11,ACC_300,ACC_001,500,1620000100
12,ACC_100,ACC_400,200,1620000110
13,ACC_400,ACC_001,200,1620000120
EOF
    chmod 644 /home/user/transactions.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
