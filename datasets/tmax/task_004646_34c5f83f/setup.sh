#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/raw_exp_A.json
[
  {"id": 1, "val": 100},
  {"id": 2, "val": 150}
]
EOF

    cat << 'EOF' > /home/user/data/exp_B_raw.csv
id,val
3,200
4,250
EOF

    cat << 'EOF' > /home/user/data/results_C_exp.json
[
  {"id": 5, "val": 300}
]
EOF

    chmod -R 777 /home/user
