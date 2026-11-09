#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip
    pip3 install pytest pandas numpy scipy scikit-learn

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/embeddings_truth.csv
id,category,v1,v2,v3
1,alpha,1.0,0.0,0.0
2,alpha,0.0,1.0,0.0
3,alpha,0.0,0.0,1.0
4,beta,1.0,1.0,0.0
5,beta,0.0,1.0,1.0
6,gamma,0.5,0.5,0.5
7,gamma,1.0,0.5,0.0
EOF

    cat << 'EOF' > /home/user/data/embeddings_model.csv
id,v1,v2,v3
1,0.9,0.1,0.0
2,0.0,0.8,0.6
3,0.1,0.1,0.9
4,1.0,1.0,0.0
5,0.0,0.5,0.5
6,0.5,0.5,0.5
7,0.8,0.2,0.1
EOF

    chmod -R 777 /home/user
