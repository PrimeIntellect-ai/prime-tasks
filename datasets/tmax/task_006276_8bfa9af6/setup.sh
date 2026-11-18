#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/synth_data
    cat << 'EOF' > /home/user/molecule.txt
1.0 1.0 1.0
0 100 0
100 0 100
0 100 0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
