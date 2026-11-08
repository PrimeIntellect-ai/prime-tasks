#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/artifacts/baseline.csv
id,val1,val2,val3,val4
base1,1.0,0.0,0.0,0.0
base2,0.0,1.0,0.0,0.0
base3,0.7071,0.7071,0.0,0.0
base4,0.5,0.5,0.5,0.5
EOF

    cat << 'EOF' > /home/user/artifacts/experiments.csv
exp_id,val1,val2,val3,val4
expA,0.99,0.05,0.0,0.0
expB,0.0,0.95,0.1,0.0
expC,0.70,0.71,0.05,0.0
expD,0.48,0.51,0.49,0.52
EOF

    chown -R user:user /home/user/artifacts
    chmod -R 777 /home/user
