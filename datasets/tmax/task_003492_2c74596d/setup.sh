#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/corpus.txt
The quick brown fox jumps over the lazy dog!
Machine learning is fascinating.
C++ is a compiled language, whereas Python is interpreted.
Data science requires statistical thinking!
The lazy dog sleeps all day.
Foxes are wild animals.
Statistical hypothesis testing is a foundation of data science.
Tokenization splits text into smaller units.
Cosine similarity measures the angle between two vectors.
Vectors are used in machine learning.
EOF

    cat << 'EOF' > /home/user/queries.txt
A quick brown fox!
Data science and statistical testing.
Vectors and cosine similarity.
Machine learning interpreted.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
