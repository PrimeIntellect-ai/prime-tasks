#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/experiments

    cat << 'EOF' > /home/user/experiments/exp1.csv
run_id,param_alpha,cv_fold_1,cv_fold_2,cv_fold_3,w_1,w_2,w_3
101,0.1,0.80,0.82,0.81,0.5,-0.2,0.1
102,0.2,0.85,0.86,0.84,0.4,0.1,0.3
EOF

    cat << 'EOF' > /home/user/experiments/exp2.csv
run_id,param_alpha,cv_fold_1,cv_fold_2,cv_fold_3,w_1,w_2,w_3
103,0.3,0.90,0.91,0.92,0.6,0.8,0.0
104,0.4,0.88,0.89,0.87,0.7,-0.7,0.2
EOF

    cat << 'EOF' > /home/user/experiments/exp3.csv
run_id,param_alpha,cv_fold_1,cv_fold_2,cv_fold_3,w_1,w_2,w_3
105.0,0.5,0.95,0.96,0.94,1.0,1.0,1.0
NaN,0.6,0.99,0.99,0.99,2.0,2.0,2.0
EOF

    cat << 'EOF' > /home/user/experiments/exp4.csv
run_id,param_alpha,cv_fold_1,cv_fold_2,cv_fold_3,w_1,w_2,w_3
106,0.1,0.70,0.75,0.72,0.1,0.1,0.1
107,0.2,0.71,0.72,0.75,0.2,0.2,0.2
EOF

    chmod -R 777 /home/user
