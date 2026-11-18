#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/nodes.csv
node_id,base_cost,node_type
PRODUCT_A,0.0,FINAL
PART_B,10.0,ASSEMBLY
PART_C,20.0,ASSEMBLY
SUBPART_D,5.0,ASSEMBLY
SUBPART_X,8.0,ASSEMBLY
RAW_E,2.0,RAW_MATERIAL
RAW_F,3.0,RAW_MATERIAL
RAW_G,1.5,RAW_MATERIAL
EOF

    cat << 'EOF' > /home/user/edges.csv
parent_id,child_id,multiplier
PRODUCT_A,PART_B,2
PRODUCT_A,PART_C,1
PART_B,SUBPART_D,3
PART_B,SUBPART_X,1
PART_C,RAW_F,4
SUBPART_D,RAW_E,5
SUBPART_X,RAW_G,2
SUBPART_X,RAW_F,1
EOF

    chmod -R 777 /home/user
