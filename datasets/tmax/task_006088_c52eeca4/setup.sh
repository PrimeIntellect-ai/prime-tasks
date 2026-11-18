#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/artifacts/exp1.json
{"experiment_id": "exp_alpha", "status": "SUCCESS", "metrics": [0.10, 0.20, 0.30, 0.40, 0.50]}
EOF

    cat << 'EOF' > /home/user/artifacts/exp2.json
{"experiment_id": "exp_beta", "status": "SUCCESS", "metrics": [0.11, 0.22, 0.29, 0.41, 0.48]}
EOF

    cat << 'EOF' > /home/user/artifacts/exp3.json
{"experiment_id": "exp_gamma", "status": "SUCCESS", "metrics": [0.90, 0.10, 0.10, 0.10, 0.10]}
EOF

    cat << 'EOF' > /home/user/artifacts/exp4.json
{"experiment_id": "exp_delta", "status": "SUCCESS", "metrics": [0.10, 0.90, 0.10, 0.10, 0.10]}
EOF

    cat << 'EOF' > /home/user/artifacts/exp5.json
{"experiment_id": "exp_epsilon", "status": "SUCCESS", "metrics": [0.10, 0.20]}
EOF

    cat << 'EOF' > /home/user/artifacts/exp6.json
{"experiment_id": "exp_zeta", "status": "FAILED", "metrics": [0.10, 0.20, 0.30, 0.40, 0.50]}
EOF

    chmod -R 777 /home/user
