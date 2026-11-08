#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/routes.csv
source,destination,cost,capacity,type
FactoryA,WarehouseB,50,100,standard
WarehouseB,StoreZ,70,80,standard
FactoryA,WarehouseC,30,40,express
WarehouseC,StoreZ,40,100,express
FactoryA,StoreZ,200,500,express
WarehouseB,FactoryA,50,100,standard
WarehouseD,StoreZ,10,200,express
FactoryA,WarehouseD,100,200,express
EOF

    chmod -R 777 /home/user
