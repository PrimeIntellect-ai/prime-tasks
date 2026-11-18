#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import random
import numpy as np
from scipy import stats

random.seed(42)

def generate_text(num_lines, mean_word_len, num_words):
    lines = []
    for _ in range(num_lines):
        words = []
        for _ in range(num_words):
            # Generate word of random length around the mean
            w_len = max(1, min(10, int(random.gauss(mean_word_len, 2))))
            words.append('a' * w_len)
        lines.append(' '.join(words) + '\n')
    return lines

os.makedirs('/home/user', exist_ok=True)

with open('/home/user/baseline.txt', 'w') as f:
    f.writelines(generate_text(500, 4.5, 20))

with open('/home/user/batch.txt', 'w') as f:
    f.writelines(generate_text(500, 5.0, 22))

def process(file):
    norms = []
    with open(file, 'r') as f:
        for line in f:
            tokens = line.strip().split()
            counts = np.zeros(10)
            for t in tokens:
                l = len(t)
                if 1 <= l <= 10:
                    counts[l-1] += 1
            norms.append(np.linalg.norm(counts))
    return np.array(norms)

base_norms = process('/home/user/baseline.txt')
batch_norms = process('/home/user/batch.txt')

res = stats.ttest_ind(batch_norms, base_norms, equal_var=False)
ci = res.confidence_interval(confidence_level=0.95)

truth_str = f"{res.statistic:.4f},{res.pvalue:.4f},{ci.low:.4f},{ci.high:.4f}"
with open('/home/user/.truth.csv', 'w') as f:
    f.write(truth_str)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
