#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /home/user/features.csv
id,f1,f2,f3
A,1.0,-50.0,0.1
B,2.0,1.0,0.2
C,,1.5,0.3
D,100.0,2.0,0.4
E,1.5,,0.5
EOF

    cat << 'EOF' > /home/user/baseline_nn.csv
id,nn1_id,nn2_id
A,B,C
B,E,C
C,B,E
D,C,B
E,B,C
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
