#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user/data /home/user/scripts /home/user/artifacts
    cat << 'EOF' > /home/user/data/corpus.txt
the quick brown fox jumps over the lazy dog
machine learning is fascinating and challenging
data science involves linear algebra and statistics
the fox is quick and the dog is lazy
statistics is the grammar of science
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
