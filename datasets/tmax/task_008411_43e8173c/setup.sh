#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/experiments/logs/

    cat << 'EOF' > /home/user/experiments/logs/run1.csv
experiment_id,learning_rate,batch_size,optimizer,val_accuracy,training_time
e1,0.01,32,adam,0.85,100
e2,0.001,64,sgd,0.80,120
e6,0.05,128,adam,0.91,150
EOF

    cat << 'EOF' > /home/user/experiments/logs/run2.csv
experiment_id,learning_rate,batch_size,optimizer,val_accuracy,training_time
e3,0.01,32,sgd,0.86,90
e4,0.001,64,adam,0.82,110
e7,0.05,128,sgd,0.89,140
EOF

    cat << 'EOF' > /home/user/experiments/logs/run3.csv
experiment_id,learning_rate,batch_size,optimizer,val_accuracy,training_time
e5,0.01,64,adam,0.88,105
e8,0.05,128,adam,0.90,145
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
