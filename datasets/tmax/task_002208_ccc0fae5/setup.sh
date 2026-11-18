#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/transactions.csv
sender,receiver,amount,timestamp
A,B,50,100
A,C,100,101
B,C,20,102
A,B,5,103
C,A,200,104
D,A,50,105
D,B,15,106
B,D,100,107
C,D,11,108
E,F,10,109
F,E,300,110
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
