#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/target.txt
CGATCGTAGCTAGCTAGCATCGTAGCTAG
EOF

    cat << 'EOF' > /home/user/primer.txt
GTAGCTA
EOF

    cat << 'EOF' > /home/user/matrix.txt
  A  C  G  T
A 5 -1 -2 -1
C -1 5 -1 -2
G -2 -1 5 -1
T -1 -2 -1 5
EOF

    chmod -R 777 /home/user
