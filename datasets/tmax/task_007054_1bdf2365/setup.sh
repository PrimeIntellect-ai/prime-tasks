#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_experiments.txt
run_001 | status: Success | params: lr_0.01, dropout_0.5, batch_32
run_002 | status: Failure | params: lr_0.01, dropout_0.2, batch_32
run_003 | status: Success | params: lr_0.05, dropout_0.5, batch_64
run_004 | status: Failure | params: lr_0.01, dropout_0.5, batch_32
run_005 | status: Success | params: lr_0.01, dropout_0.5, batch_16
run_006 | status: Success | params: lr_0.02, dropout_0.5, batch_32
run_007 | status: Failure | params: lr_0.01, dropout_0.5, batch_64
run_008 | status: Success | params: lr_0.01, dropout_0.2, batch_32
run_009 | status: Failure | params: lr_0.10, dropout_0.5, batch_16
run_010 | status: Success | params: lr_0.05, dropout_0.5, batch_32
EOF

    chmod -R 777 /home/user
