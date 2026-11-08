#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx pandas

    mkdir -p /home/user
    cat << 'EOF' > /home/user/transactions.csv
tx_id,from_node,to_node,timestamp,weight
TX01,A,B,1620000001,100
TX02,B,C,1620000002,150
TX03,C,D,1620000003,200
TX04,D,A,1620000004,50
TX05,C,E,1620000005,300
TX06,E,F,1620000006,250
TX07,F,C,1620000007,250
TX08,F,G,1620000008,400
TX09,G,B,1620000009,80
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
