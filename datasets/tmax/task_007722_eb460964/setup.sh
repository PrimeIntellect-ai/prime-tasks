#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
id,name,type
N001,MainFactory,factory
N002,WarehouseA,warehouse
N003,WarehouseB,warehouse
N004,WarehouseC,warehouse
N005,WarehouseD,warehouse
N006,WarehouseE,warehouse
N007,WarehouseF,warehouse
N008,RetailA,retail
N009,WarehouseG,warehouse
N010,WarehouseH,warehouse
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target,distance
N001,N002,20
N001,N003,50
N002,N004,40
N002,N005,60
N003,N006,30
N003,N007,110
N004,N008,10
N004,N009,40
N005,N009,30
N006,N010,70
N001,N006,90
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
