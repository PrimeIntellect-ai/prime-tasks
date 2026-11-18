#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/protein_features.csv
1.0, 2.0, 3.0, 10.0
2.0, 4.0, 6.0, 20.0
1.5, 3.1, 4.5, 15.2
0.5, 0.9, 1.6, 4.8
3.0, 6.1, 9.0, 30.5
EOF

    chmod -R 777 /home/user
