#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.csv
id,type,name
1,Company,Acme Corp
2,Supplier,Global Supplies
3,Supplier,Fast Parts
4,Customer,Big Retail
5,Supplier,Hidden Gems
6,Company,Beta Inc
7,Supplier,Distant Parts
8,Customer,Small Shop
9,Supplier,Indirect Goods
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target,relation
1,2,buys_from
1,3,buys_from
4,1,sells_to
6,1,partner
1,5,buys_from
6,5,buys_from
6,7,buys_from
8,6,sells_to
2,9,buys_from
EOF

    chmod -R 777 /home/user
