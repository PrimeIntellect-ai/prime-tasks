#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/accounts.csv
account_id,risk_level
ACC_101,high_risk
ACC_102,offshore
ACC_103,high_risk
ACC_104,offshore
ACC_105,low_risk
ACC_106,high_risk
ACC_107,offshore
ACC_108,high_risk
ACC_109,low_risk
ACC_110,high_risk
ACC_111,offshore
ACC_112,high_risk
EOF

    cat << 'EOF' > /home/user/transactions.csv
tx_id,source,target,amount
TX_01,ACC_105,ACC_106,2000
TX_02,ACC_106,ACC_107,3000
TX_03,ACC_107,ACC_105,4000
TX_04,ACC_101,ACC_102,4000
TX_05,ACC_102,ACC_103,3500
TX_06,ACC_103,ACC_104,2000
TX_07,ACC_104,ACC_101,1500
TX_08,ACC_110,ACC_111,1000
TX_09,ACC_111,ACC_112,1500
TX_10,ACC_112,ACC_108,2000
TX_11,ACC_108,ACC_110,1200
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
