#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/raw_metrics.csv
request_id,payload_size,compute_cycles
REQ001,2048,5000000
REQ002,1024,1000000
REQ003,8192,20000000
REQ004,512,500000
REQ005,4096,12000000
REQ006,3072,6000000
REQ007,1536,2500000
EOF

    cat << 'EOF' > /home/user/pipeline/model_weights.json
{"w1": 0.5, "w2": 0.8, "bias": -2.0}
EOF

    cat << 'EOF' > /home/user/pipeline/priors.json
{"P_Anomaly": 0.05, "P_Normal": 0.95}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
