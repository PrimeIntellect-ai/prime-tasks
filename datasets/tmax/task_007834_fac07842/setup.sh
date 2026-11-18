#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/train.csv
id,category,abstract
t1,AI,Deep learning models use neural networks for prediction.
t2,AI,Machine learning algorithms classify data points efficiently.
t3,DB,Relational database management systems optimize SQL queries.
t4,DB,NoSQL databases scale horizontally for big data.
t5,AI,Neural networks and deep learning improve image recognition.
EOF

    cat << 'EOF' > /home/user/data/test.csv
id,category,abstract
q1,AI,Deep learning models classify image data efficiently.
q2,DB,SQL databases optimize big data queries.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
