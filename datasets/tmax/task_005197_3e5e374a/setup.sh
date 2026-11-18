#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import random

np.random.seed(42)
random.seed(42)

n_rows = 1000
ids = list(range(1, n_rows + 1))

words = ["good", "bad", "excellent", "terrible", "okay", "average", "amazing", "awful", "product", "item", "quality", "price", "delivery", "slow", "fast"]

texts = []
for _ in range(n_rows):
    length = random.randint(5, 50)
    text = " ".join(random.choices(words, k=length))
    texts.append(text)

ratings = []
for t in texts:
    score = 3
    if "good" in t or "excellent" in t or "amazing" in t: score += 1
    if "bad" in t or "terrible" in t or "awful" in t: score -= 1
    score = max(1, min(5, score))
    ratings.append(score)

corrupted_indices = random.sample(range(n_rows), 200)
for idx in corrupted_indices:
    corruption_type = random.choice(['nan', 'high', 'low'])
    if corruption_type == 'nan':
        ratings[idx] = np.nan
    elif corruption_type == 'high':
        ratings[idx] = random.randint(10, 100)
    else:
        ratings[idx] = random.randint(-50, 0)

missing_text_indices = random.sample(range(n_rows), 20)
for idx in missing_text_indices:
    texts[idx] = np.nan

df = pd.DataFrame({"id": ids, "text": texts, "rating": ratings})
df.to_csv("/home/user/reviews.csv", index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
