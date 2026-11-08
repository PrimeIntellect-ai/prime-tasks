#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/experiment_data.csv
experiment_id,group,trials,successes,temperature,pressure,outcome_class
1,A,10,7,20.5,1.0,1
2,B,12,5,22.1,1.1,0
3,A,15,12,21.0,1.2,1
4,A,8,3,19.5,0.9,0
5,B,10,4,23.0,1.3,0
EOF

    chmod -R 777 /home/user
