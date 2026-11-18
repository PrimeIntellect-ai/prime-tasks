#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user/experiments

    cat << 'EOF' > /home/user/experiments/model_A.csv
id,y_true,y_pred
1,1.0,1.1
2,2.0,1.9
3,3.0,3.2
EOF

    cat << 'EOF' > /home/user/experiments/model_B.csv
id,y_true,y_pred
1,1.0,1.5
2,2.0,2.5
3,3.0,3.5
EOF

    cat << 'EOF' > /home/user/experiments/model_C.csv
id,y_true,y_pred
1,1.0,2.0
2,2.0,3.0
3,3.0,4.0
EOF

    cat << 'EOF' > /home/user/experiments/model_D.csv
id,y_true,y_pred
1,1.0,1.05
2,2.0,1.95
3,3.0,3.05
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
