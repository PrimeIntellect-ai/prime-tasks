#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/models.csv
model_id,model_type,hyperparams
1,ResNet,lr=0.01
2,Transformer,lr=0.001
3,VGG,lr=0.05
4,MLP,lr=0.1
EOF

    cat << 'EOF' > /home/user/evals.csv
model_id,run_id,accuracy,loss
1,r1,0.85,0.2
1,r2,0.88,0.18
1,r3,err,0.15
2,r4,0.92,0.1
2,r5,0.95,0.08
3,r6,0.70,0.5
3,r7,0.72,-0.1
4,r8,1.2,0.4
4,r9,0.9,0.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
