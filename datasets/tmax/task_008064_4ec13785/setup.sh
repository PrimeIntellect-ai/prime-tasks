#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/data /home/user/output

    cat << 'EOF' > /home/user/data/products.csv
id,feature1,feature2,feature3,price
P001,10.0,5.0,2.0,40.0
P002,12.0,4.0,2.5,45.0
P003,5.0,2.0,1.0,20.0
P004,10.5,5.2,1.8,42.0
P005,2.0,1.0,0.5,50.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
