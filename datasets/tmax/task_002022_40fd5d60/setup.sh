#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data
cd /home/user/data

# Generate deterministic data
python3 -c "
import gzip
with gzip.open('vector_a.txt.gz', 'wt') as fa, gzip.open('vector_b.txt.gz', 'wt') as fb:
    for i in range(1, 10001):
        fa.write(f'{i * 0.5:.2f}\n')
        fb.write(f'{i * 1.2 + (i % 5) * 2.0:.2f}\n')
"

# Calculate expected values
python3 -c "
import gzip
import numpy as np

with gzip.open('vector_a.txt.gz', 'rt') as fa, gzip.open('vector_b.txt.gz', 'rt') as fb:
    a = np.array([float(x) for x in fa])
    b = np.array([float(x) for x in fb])

dot_product = np.dot(a, b)
correlation = np.corrcoef(a, b)[0, 1]

with open('/tmp/expected_metrics.log', 'w') as f:
    f.write(f'DOT_PRODUCT={dot_product:.2f}\n')
    f.write(f'CORRELATION={correlation:.4f}\n')
"

chmod -R 777 /home/user
