#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/input_graph.csv
node_id,parent_id,node_name
1,0,Electronics
2,1,Computers
3,2,Laptops
4,2,Desktops
5,0,Home
6,5,Furniture
7,6,Chairs
8,6,Tables
9,1,Audio
10,9,Headphones
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
