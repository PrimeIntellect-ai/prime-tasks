#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/embeddings.csv
Word,v1,v2,v3,v4,v5
apple,0.5,0.1,0.2,-0.1,0.8
banana,0.4,0.15,0.25,-0.05,0.75
car,0.1,0.8,-0.5,0.4,0.1
truck,0.15,0.7,-0.4,0.5,0.05
dog,0.9,-0.2,0.1,0.1,0.1
cat,0.8,-0.1,0.2,0.0,0.2
EOF

    chmod -R 777 /home/user
