#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn pydantic numpy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup_data.py
import pandas as pd
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)

np.random.seed(42)
categories = ['electronics', 'clothing', 'books']
data = []
for i in range(300):
    cat = np.random.choice(categories)
    if cat == 'electronics':
        words = ['screen', 'battery', 'cable', 'power', 'device', 'smart']
    elif cat == 'clothing':
        words = ['shirt', 'cotton', 'size', 'wear', 'shoes', 'color']
    else:
        words = ['pages', 'author', 'read', 'book', 'cover', 'story']

    text = " ".join(np.random.choice(words, 10))
    data.append({
        'product_id': i,
        'text': text,
        'label': cat
    })

# Add some invalid rows
data.append({'product_id': 'invalid', 'text': 'bad row', 'label': 'electronics'})
data.append({'product_id': 301, 'text': None, 'label': 'clothing'})

df = pd.DataFrame(data)
df.to_csv('/home/user/products.csv', index=False)
EOF

    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
