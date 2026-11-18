#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/experiments.csv
id,model_name,accuracy,loss
1,BetaNet,0.85,0.40
2,BetaNet,0.88,0.30
3,BetaNet,,0.35
4,BetaNet,0.90,-0.10
5,AlphaNet,0.92,0.20
6,BetaNet,0.82,0.50
7,BetaNet,0.86,0.38
8,BetaNet,1.20,0.10
9,BetaNet,0.89,0.25
10,BetaNet,0.81,0.55
11,BetaNet,NaN,0.40
12,BetaNet,0.87,0.32
EOF

    chmod -R 777 /home/user
