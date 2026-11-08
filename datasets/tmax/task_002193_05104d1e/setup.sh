#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backups.csv
id,parent_id,type,size_bytes,status
B01,,FULL,5000,OK
B02,B01,INCREMENTAL,500,OK
B03,B02,INCREMENTAL,250,OK
B04,B03,INCREMENTAL,100,CORRUPT
B05,B04,INCREMENTAL,50,OK
C01,,FULL,4000,CORRUPT
C02,C01,INCREMENTAL,400,OK
D01,,FULL,6000,OK
D02,D01,INCREMENTAL,600,OK
EOF

    chmod -R 777 /home/user
