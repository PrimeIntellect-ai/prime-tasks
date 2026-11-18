#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/configs.csv
run_id,model_type
run1,ResNet
run2,VGG
run3,ResNet
run4,Transformer
run5,VGG
EOF

    cat << 'EOF' > /home/user/metrics.csv
run_id,m1,m2,m3,m4,m5
run1,0.9,0.1,10.0,5.0,2.2
run2,0.8,0.2,15.0,4.0,3.1
run3,0.95,0.05,12.0,6.0,2.5
run4,0.98,0.02,20.0,8.0,4.0
run5,0.85,0.15,14.0,4.5,2.9
EOF

    cat << 'EOF' > /home/user/weights.txt
0.5
-0.2
-0.01
0.1
-0.05
EOF

    chmod -R 777 /home/user
