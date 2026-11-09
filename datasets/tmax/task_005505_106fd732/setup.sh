#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user/model /home/user/data /home/user/output

    cat << 'EOF' > /home/user/model/weights.csv
the,1.0,0.0
quick,0.5,0.5
brown,0.0,1.0
fox,1.0,1.0
lazy,-1.0,0.0
dog,-0.5,-0.5
sleeps,0.0,-1.0
EOF

    cat << 'EOF' > /home/user/data/doc1.txt
the quick brown fox
EOF

    cat << 'EOF' > /home/user/data/doc2.txt
lazy dog sleeps
EOF

    cat << 'EOF' > /home/user/data/doc3.txt
quick brown dog
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
