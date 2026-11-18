#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
id,text,price
1,The quick brown fox,10.5
2,Jumps over the lazy dog,15.0
3,Machine learning is fascinating,20.0
4,Data science requires math,12.5
5,Reproducibility is key for pipelines,9.99
EOF

    chmod -R 777 /home/user
