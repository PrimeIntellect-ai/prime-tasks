#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
id,split,text
1,train,apple
2,train,
3,test,banana
4,ignore,carrot
5,train,dog
6,test,elephant
7,train, 
8,test,frog
9,train,giraffe
10,ignore,hippo
EOF

    cat << 'EOF' > /home/user/embed.py
import sys
import csv

if len(sys.argv) != 3:
    sys.exit("Usage: python3 embed.py <input.tsv> <output.csv>")

with open(sys.argv[1], 'r') as fin, open(sys.argv[2], 'w') as fout:
    for line in fin:
        parts = line.strip().split('\t')
        if len(parts) < 2: continue
        id_val = parts[0]
        text = parts[1]
        # mock embedding
        emb = [float(len(text) + i) for i in range(10)]
        fout.write(f"{id_val}," + ",".join(map(str, emb)) + "\n")
EOF

    cat << 'EOF' > /home/user/evaluate.py
import sys

if len(sys.argv) != 5:
    sys.exit("Usage: python3 evaluate.py <train.csv> <test.csv> <K> <T>")

train_file = sys.argv[1]
test_file = sys.argv[2]
K = int(sys.argv[3])
T = float(sys.argv[4])

with open(train_file, 'r') as f:
    train_lines = len(f.readlines())
with open(test_file, 'r') as f:
    test_lines = len(f.readlines())

# Deterministic mock score based on row counts and parameters
# clean_train.tsv should have 3 rows (1, 5, 9)
# clean_test.tsv should have 3 rows (3, 6, 8)
# If ETL is correct, train_lines=3, test_lines=3. Total = 6.
base_score = (train_lines + test_lines) * 10.0  # 60.0
penalty = abs(K - 6) * 2.5 + abs(T - 0.5) * 10.0
score = base_score - penalty

print(f"{score:.2f}")
EOF

    chmod -R 777 /home/user
