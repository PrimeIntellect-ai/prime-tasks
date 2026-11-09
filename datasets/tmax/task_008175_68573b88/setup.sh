#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
id,feature_A,feature_B,target,split
1,10.5,100.0,1,train
2,12.1,150.0,0,train
3,9.8,120.0,1,train
4,11.0,90.0,0,train
5,10.0,200.0,1,test
6,13.2,80.0,0,test
7,10.5,150.0,1,test
EOF

    chmod -R 777 /home/user
