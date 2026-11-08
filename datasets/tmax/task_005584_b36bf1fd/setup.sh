#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/eval_results.csv
model_id,trials,successes
model_A,500,410
model_B,500,425
EOF

    chmod -R 777 /home/user
