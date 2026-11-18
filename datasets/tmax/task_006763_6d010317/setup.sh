#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest pandas networkx

    # Create user
    useradd -m -s /bin/bash user || true

    # Create locations.csv
    cat << 'EOF' > /home/user/locations.csv
loc_id,loc_name
1,Warehouse_Alpha
2,Hub_Beta
3,Hub_Gamma
4,Hub_Delta
5,Store_Omega
6,Decoy_Hub
EOF

    # Create routes.csv
    cat << 'EOF' > /home/user/routes.csv
source_id,dest_id,distance
1,2,20
1,3,50
1,6,10
6,5,100
2,3,10
2,4,40
3,4,10
3,5,60
4,5,20
EOF

    # Set permissions
    chmod -R 777 /home/user
