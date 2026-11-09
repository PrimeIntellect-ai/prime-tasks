#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin
    cat << 'EOF' > /home/user/ml_metrics.csv
run_id,epoch,loss,accuracy
runA,1,0.85,0.72
runA,2,,0.75
runA,3,0.60,1.20
runB,1,0.90,0.60
runB,2,0.80,-0.10
runB,3,,0.85
EOF

    chmod -R 777 /home/user
