#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn pyarrow

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np
import random
import string

np.random.seed(42)
random.seed(42)

def generate_random_text(num_words=10):
    words = ['research', 'data', 'science', 'experiment', 'learning', 'machine', 'python', 'algorithm', 'model', 'dataset', 'token', 'outlier', 'pca', 'dimension', 'scale', 'big', 'analysis', 'compute', 'storage', 'tracking']
    return ' '.join(random.choices(words, k=num_words))

data = []
for i in range(1000):
    id_val = f"doc_{i}"

    # Generate text with some missing
    if random.random() < 0.05:
        text = np.nan if random.random() < 0.5 else ""
    else:
        text = generate_random_text(random.randint(5, 15))

    # Generate ages with outliers
    rand_val = random.random()
    if rand_val < 0.1:
        age = random.randint(-50, 10) # Outlier low
    elif rand_val < 0.2:
        age = random.randint(101, 200) # Outlier high
    elif rand_val < 0.25:
        age = np.nan # Missing
    else:
        age = random.randint(15, 100) # Valid

    data.append([id_val, text, age])

df = pd.DataFrame(data, columns=['id', 'text', 'author_age'])
df.to_csv('/home/user/raw_dataset.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    chmod -R 777 /home/user
