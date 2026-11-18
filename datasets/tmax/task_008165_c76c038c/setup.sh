#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest pandas numpy

    mkdir -p /home/user/experiments/embeddings

    cat << 'EOF' > /home/user/experiments/metadata.csv
model_id,epoch,embedding_file
model_A,10,emb_A.txt
model_B,10,emb_B.txt
model_C,10,emb_C.txt
model_D,10,emb_D.txt
model_E,10,emb_E.txt
EOF

    echo "1.0 1.0 1.0 1.0 1.0" > /home/user/experiments/embeddings/emb_A.txt
    echo "0.0 0.0 0.0 0.0 0.0" > /home/user/experiments/embeddings/emb_B.txt
    echo "1.0 NaN 1.0 1.0 1.0" > /home/user/experiments/embeddings/emb_C.txt
    echo "1.0 1.0 1.0" > /home/user/experiments/embeddings/emb_D.txt
    echo "2.0 2.0 2.0 2.0 2.0" > /home/user/experiments/embeddings/emb_E.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
