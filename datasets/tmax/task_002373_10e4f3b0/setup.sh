#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/experiments.csv
experiment_id,learning_rate,batch_size,latency_ms,accuracy
1,0.01,32,10,0.80
2,0.005,64,15,0.85
3,0.001,128,20,0.88
4,0.0005,256,25,0.90
5,0.0001,512,30,0.92
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
