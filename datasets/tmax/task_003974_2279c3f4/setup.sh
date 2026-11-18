#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backups.csv
backup_id,timestamp,size_mb,type
b01,2023-10-01,2000,FULL
b02,2023-10-02,150,INC
b03,2023-10-03,200,INC
b04,2023-10-04,50,INC
b05,2023-10-01,1500,FULL
b06,2023-10-02,300,INC
b07,2023-10-03,400,INC
b08,2023-10-01,2400,FULL
b09,2023-10-02,50,INC
EOF

    cat << 'EOF' > /home/user/dependencies.csv
backup_id,parent_id
b02,b01
b03,b02
b04,b03
b06,b05
b07,b06
b09,b08
EOF

    chmod -R 777 /home/user
