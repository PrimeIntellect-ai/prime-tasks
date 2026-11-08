#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scikit-learn numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/dataset.jsonl
{"id": 1, "text": "The quick brown fox jumps over the lazy dog.", "split": "train"}
{"id": 2, "text": "Data science is an interdisciplinary field that uses scientific methods.", "split": "train"}
{"id": 3, "text": "Bayesian inference is a method of statistical inference.", "split": "train"}
{"id": 4, "text": "Python is a high-level, general-purpose programming language.", "split": "train"}
{"id": 5, "text": "The quick brown fox jumps over the lazy dog.", "split": "test"}
{"id": 6, "text": "Data science is interdisciplinary and uses scientific methods.", "split": "test"}
{"id": 7, "text": "I love eating pizza with pineapple.", "split": "test"}
{"id": 8, "text": "A totally unrelated text about space exploration.", "split": "test"}
{"id": 9, "text": "Python is a high-level, general-purpose programming language.", "split": "test"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
