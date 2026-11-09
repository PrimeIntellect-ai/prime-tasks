#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/incoming.csv
id,x1,x2,model_output
1,2.0,3.0,11.5
2,foo,3.0,10.0
3,4.0,1.0,20.0
4,1e200,1.0,0.0
5,10.0,5.0,65.2
6,6.0,2.0,
7,0.0,0.0,1.5
8,1e250,1e250,1.0
9,-2.0,1.0,5.0
EOF

    chmod -R 777 /home/user
