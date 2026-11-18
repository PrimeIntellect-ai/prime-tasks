#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/setup.py
import pandas as pd
import numpy as np
import random
import os

os.makedirs('/home/user/data', exist_ok=True)

np.random.seed(42)
random.seed(42)

vocab = ['apple', 'banana', 'cherry', 'date', 'elderberry', 'fig', 'grape', 'honeydew', 'kiwi', 'lemon']

data = []
for i in range(500):
    words = random.choices(vocab, k=random.randint(5, 15))
    text = " ".join(words)
    target = 1.0 if 'apple' in words else 0.0
    if random.random() < 0.2:
        target = np.nan
    data.append({'text': text, 'target': target})

df = pd.DataFrame(data)
df.to_csv('/home/user/data/dataset.csv', index=False)
EOF

    python3 /home/user/setup.py

    chmod -R 777 /home/user
