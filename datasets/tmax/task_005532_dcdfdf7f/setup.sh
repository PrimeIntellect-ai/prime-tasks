#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create dataset.csv
    echo "col1,col2,col3,label" > /home/user/dataset.csv
    for i in $(seq 1 100); do
      echo "$RANDOM,$RANDOM,$RANDOM,$((i % 2))" >> /home/user/dataset.csv
    done

    # Create model.py
    cat << 'EOF' > /home/user/model.py
import argparse
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--train', required=True)
parser.add_argument('--test', required=True)
parser.add_argument('--pca', action='store_true')
args = parser.parse_args()

with open(args.train, 'r') as f:
    train_len = len(f.readlines())
with open(args.test, 'r') as f:
    test_len = len(f.readlines())

if train_len == 80 and test_len == 20 and args.pca:
    # Deterministic accuracy based on sizes to ensure the bash logic works
    print("Accuracy: 0.85")
else:
    print("Accuracy: 0.00")
EOF

    chmod -R 777 /home/user
