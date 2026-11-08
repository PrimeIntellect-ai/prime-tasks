#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backups.csv
id,db_name,type,parent_id,size_bytes,timestamp
b1,auth_db,full,none,1024,10000
b2,auth_db,inc,b1,128,10010
b3,auth_db,inc,b2,256,10020
b4,auth_db,full,none,2048,10050
b5,auth_db,inc,b4,512,10060
b6,auth_db,inc,b5,128,10070
b7,auth_db,inc,b6,64,10080
b8,auth_db,inc,b7,32,10090
b9,auth_db,inc,missing_parent,100,10100
b10,billing_db,full,none,5000,10000
b11,billing_db,inc,b10,500,10010
EOF

    chmod -R 777 /home/user
