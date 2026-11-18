#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    # Create experiments.csv
    cat << 'EOF' > /home/user/experiments.csv
run_id,model_type,deploy_status
1,alpha,deployed
2,alpha,deployed
3,alpha,failed
4,beta,deployed
5,beta,deployed
7,beta,deployed
EOF

    # Create metrics.json
    cat << 'EOF' > /home/user/metrics.json
[
    {"run_id": 1, "errors_detected": 5},
    {"run_id": 2, "errors_detected": 3},
    {"run_id": 3, "errors_detected": 10},
    {"run_id": 4, "errors_detected": 2},
    {"run_id": 5, "errors_detected": 1},
    {"run_id": 6, "errors_detected": 0},
    {"run_id": 7, "errors_detected": 4}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
