#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
record_id,dataset_split,val_x,val_y
1,train,10,4
2,train,20,NA
3,train,-5,30
4,train,20,8
5,test,15,10
6,test,25,12
7,train,30,12
8,test,,22
EOF
    chmod 644 /home/user/raw_data.csv

    chmod -R 777 /home/user
