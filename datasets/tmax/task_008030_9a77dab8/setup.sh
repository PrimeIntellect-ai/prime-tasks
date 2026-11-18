#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/embeddings.csv
category,v1,v2,v3
alpha,1.0,2.0,3.0
alpha,1.2,1.8,3.1
alpha,error,1.0,1.0
beta,4.0,0.5,1.0
beta,4.2,0.7,1.2
gamma,0.0,10.0,0.0
gamma,missing,,
delta,1.0,1.0,-10.0
delta,1.0,1.0,-12.0
EOF

    chmod -R 777 /home/user
