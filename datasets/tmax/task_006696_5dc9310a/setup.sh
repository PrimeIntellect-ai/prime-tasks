#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/ml_prep

    cat << 'EOF' > /home/user/raw_data.csv
id,feature_a,feature_b,category
1,10.5,20.1,cat1
2,11.0,19.5,cat2
3,error,18.0,cat1
4,12.5,22.4,cat3
5,9.0,21.0,cat1
bad_id,10.0,20.0,cat2
6,10.2,19.9,cat3
7,11.5,18.5,cat1
8,10.8,missing,cat2
9,13.0,23.1,cat1
10,9.5,20.5,cat2
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
