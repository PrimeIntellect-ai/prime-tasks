#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas numpy

    mkdir -p /home/user/data
    mkdir -p /home/user/model
    mkdir -p /home/user/output

    cat << 'EOF' > /tmp/setup.py
import os
import json
import numpy as np
import pandas as pd

# Create directories
os.makedirs("/home/user/data", exist_ok=True)
os.makedirs("/home/user/model", exist_ok=True)
os.makedirs("/home/user/output", exist_ok=True)

# 1. Create vocab.json
vocab = {"<UNK>": 0, "the": 1, "product": 2, "is": 3, "great": 4, "terrible": 5, "okay": 6, 
         "i": 7, "love": 8, "it": 9, "hate": 10, "not": 11, "bad": 12, "good": 13, "excellent": 14,
         "quality": 15, "poor": 16, "value": 17, "for": 18, "money": 19, "works": 20, "well": 21,
         "broken": 22, "arrived": 23, "late": 24, "fast": 25, "shipping": 26, "recommend": 27}
with open("/home/user/model/vocab.json", "w") as f:
    json.dump(vocab, f)

# 2. Create model weights
np.random.seed(42)
vocab_size = len(vocab)
embeddings = np.random.randn(vocab_size, 32).astype(np.float32)
linear_w = np.random.randn(16, 32).astype(np.float32)
linear_b = np.random.randn(16).astype(np.float32)

np.save("/home/user/model/embeddings.npy", embeddings)
np.save("/home/user/model/linear_w.npy", linear_w)
np.save("/home/user/model/linear_b.npy", linear_b)

# 3. Create reviews.csv
reviews = [
    {"id": "R01", "text": "The product is great! I love it."},
    {"id": "R02", "text": "Terrible product, arrived broken."},
    {"id": "R03", "text": "Works well, good value for money."},
    {"id": "R04", "text": "I hate it. Poor quality and late shipping."},
    {"id": "R05", "text": "Excellent quality, fast shipping, highly recommend!"},
    {"id": "R06", "text": "The product is good! I like it."},
    {"id": "R07", "text": "Bad product, arrived damaged."},
    {"id": "R08", "text": "Not bad, okay value."},
    {"id": "R09", "text": "Excellent! Love the fast shipping."},
    {"id": "R10", "text": "Terrible, terrible, terrible."}
]
pd.DataFrame(reviews).to_csv("/home/user/data/reviews.csv", index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
