#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/tx.csv
tx_id,date,currency,amount
1,2023-10-01,EUR,100.00
2,2023-10-01,GBP,50.00
3,2023-10-02,EUR,200.00
4,2023-10-02,GBP,10.00
5,2023-10-03,JPY,10000.00
EOF

    cat << 'EOF' > /home/user/data/fx.csv
date,currency,rate
2023-10-01,EUR,1.05
2023-10-01,GBP,1.21
2023-10-02,EUR,1.06
2023-10-02,GBP,1.20
2023-10-03,JPY,0.0067
EOF

    cat << 'EOF' > /home/user/data/expected.csv
date,total_usd
2023-10-01,165.50
2023-10-02,224.00
2023-10-03,67.00
EOF

    chmod -R 777 /home/user
