#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/corpus.txt
Data analysis is crucial for insights.
Machine learning models require training.
The quick brown fox jumps over the lazy dog.
Accelerated computing relies on GPUs.
AI accelerates the pace of scientific discovery.
Deep learning is a subset of machine learning.
Data science combines statistics and programming.
Natural language processing understands text.
Computer vision analyzes images.
Data engineers build pipelines.
EOF

    cat << 'EOF' > /home/user/word_vectors.csv
machine,1.0,0.0,0.5,0.0,0.2
learning,0.8,0.2,0.4,0.1,0.0
accelerates,0.0,0.9,0.0,0.8,0.1
data,0.5,0.0,0.8,0.0,0.0
analysis,0.4,0.1,0.7,0.0,0.0
models,0.7,0.0,0.3,0.0,0.1
ai,0.9,0.1,0.6,0.0,0.1
science,0.3,0.1,0.5,0.2,0.0
EOF

    chmod -R 777 /home/user
