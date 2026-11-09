#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/experiment_logs.txt
[INFO] Exp_ID: A1 | LR: 1.0 | BS: 32 | ValLoss: 5.0 | Acc: 0.80
[INFO] Exp_ID: A2 | LR: 2.0 | BS: 32 | ValLoss: 4.0 | Acc: 0.82
[INFO] Exp_ID: A3 | LR: 3.0 | BS: 64 | ValLoss: 3.0 | Acc: 0.85
[INFO] Exp_ID: A4 | LR: 4.0 | BS: 64 | ValLoss: 3.0 | Acc: 0.86
[INFO] Exp_ID: A5 | LR: 5.0 | BS: 128 | ValLoss: 1.0 | Acc: 0.89
EOF

    chmod -R 777 /home/user
