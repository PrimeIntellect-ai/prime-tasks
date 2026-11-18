#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo socat
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat <<EOF > /home/user/accounts.csv
dev_alpha,12
dev_beta,25
ops_gamma,40
EOF

    chmod -R 777 /home/user
