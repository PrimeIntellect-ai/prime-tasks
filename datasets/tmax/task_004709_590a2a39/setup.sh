#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep bash
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/edge_ml/

    cat << 'EOF' > /home/user/edge_ml/raw_data.csv
1,2.0,3.0,1.0,4.0,2.0,1.5
2,0.0,0.0,0.0,0.0,0.0,0.5
error,1,2,3,4,5,6
3,1.0,1.0,1.0,1.0,1.0,1.0
4,-1.0,2.0,0.5,1.5,0.0,-1.0
5,1.0,2.0,NaN,4.0,5.0,1.0
6,1.0,2.0,3.0,4.0
7,1.0,2.0,3.0,4.0,5.0,6.0,7.0
EOF

    cat << 'EOF' > /home/user/edge_ml/model_weights.txt
0.5
1.0
-1.0
2.0
0.0
0.5
EOF

    chmod -R 777 /home/user
