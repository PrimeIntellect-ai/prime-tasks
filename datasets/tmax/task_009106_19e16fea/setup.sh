#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/train.tsv
1	Bayesian inference is great for probabilistic modeling
0	Tokenization splits text into words
1	Probabilistic classification uses Bayes rule
0	Dataset preparation involves cleaning text
EOF

    cat << 'EOF' > /home/user/test.txt
Probabilistic modeling involves Bayes
Text tokenization cleaning
EOF

    chmod -R 777 /home/user
