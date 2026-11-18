#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential coreutils gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/experiments.txt
id pca_components
1 10
2 50
3 10
4 10
5 50
6 10
7 10
EOF

    cat << 'EOF' > /home/user/metrics.txt
id accuracy
1 0.81
2 0.88
3 0.83
4 0.80
5 0.89
6 0.82
7 0.84
EOF

    chmod -R 777 /home/user
