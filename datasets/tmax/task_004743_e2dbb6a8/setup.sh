#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/datasets
    cat << 'EOF' > /home/user/datasets/doc1.txt
Data analysis is critical. Data data data! Science is also science.
EOF
    cat << 'EOF' > /home/user/datasets/doc2.txt
The machine learning model needs more data. Algorithms and algorithms.
EOF
    cat << 'EOF' > /home/user/datasets/doc3.txt
Data science involves linear algebra. Algebra is fundamental to algorithms.
EOF
    cat << 'EOF' > /home/user/datasets/doc4.txt
Nothing to see here, just some random text without much meaning.
EOF
    cat << 'EOF' > /home/user/datasets/doc5.txt
Science data algorithms algebra algebra algebra!
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
