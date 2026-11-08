#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/items.csv
item_id,item_name,item_type
PROD-001,SuperWidget,product
PROD-002,MegaWidget,product
SUB-A,WidgetBase,subassembly
SUB-B,WidgetCore,subassembly
PART-X,BasePlate,part
PART-Y,CoreProcessor,part
PART-Z,CoreMemory,part
RAW-1,SteelSheet,raw_material
RAW-2,SiliconWafer,raw_material
RAW-3,CopperWire,raw_material
EOF

    cat << 'EOF' > /home/user/data/bom.csv
parent_id,child_id,quantity
PROD-001,SUB-A,2
PROD-001,SUB-B,1
PROD-002,SUB-A,1
PROD-002,SUB-B,2
SUB-A,PART-X,3
SUB-A,PART-Y,2
SUB-B,PART-Y,4
SUB-B,PART-Z,1
PART-X,RAW-1,1
PART-Y,RAW-2,2
PART-Z,RAW-3,5
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
