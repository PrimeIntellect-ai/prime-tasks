#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/backup_metadata.csv
backup_id,parent_backup_id,size_mb,status
bkp_001,NONE,5000,SUCCESS
bkp_002,bkp_001,250,SUCCESS
bkp_003,bkp_001,300,SUCCESS
bkp_004,bkp_002,150,FAILED
bkp_005,bkp_003,120,SUCCESS
bkp_006,bkp_005,90,SUCCESS
bkp_007,bkp_006,45,SUCCESS
bkp_008,bkp_004,60,SUCCESS
bkp_009,bkp_008,30,SUCCESS
EOF

    chmod -R 777 /home/user
