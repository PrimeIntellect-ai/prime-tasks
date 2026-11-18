#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/mcmc_samples.csv
1.2
2.4
3.1
2.8
1.9
2.2
3.5
2.7
1.8
2.5
EOF

    chmod -R 777 /home/user
