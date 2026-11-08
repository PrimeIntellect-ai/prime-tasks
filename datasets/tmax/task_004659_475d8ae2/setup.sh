#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/params.csv
exp_id,learning_rate,epochs,initial_loss
1,0.01,10,2.5
2,-0.01,5,3.0
3,0.05,20,1.8
4,0.001,0,2.0
5,0.1,50,4.0
6,0.02,15,-1.0
7,0.01,5,1.0
EOF

    cat << 'EOF' > /home/user/metrics.csv
exp_id,final_loss
1,0.2
2,0.5
3,0.1
4,2.0
5,0.05
6,0.5
7,0.2
EOF

    chmod -R 777 /home/user
