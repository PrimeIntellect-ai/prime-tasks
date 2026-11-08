#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/nodes.csv
id,type,size_gb
s3_deep_archive,storage,1000
archive_tier2,storage,800
fast_restore_appliance,appliance,500
stage_db,database,200
prod_main_db,database,250
dr_standby,database,250
EOF

    cat << 'EOF' > /home/user/edges.csv
source,target,restore_time_min
s3_deep_archive,archive_tier2,120
s3_deep_archive,fast_restore_appliance,30
fast_restore_appliance,stage_db,10
archive_tier2,stage_db,5
stage_db,prod_main_db,5
fast_restore_appliance,prod_main_db,25
stage_db,dr_standby,15
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
