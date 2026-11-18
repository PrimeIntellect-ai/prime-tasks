#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import os
import pandas as pd
import numpy as np

np.random.seed(42)

data = []
products = list(range(100, 150))

vocab_excellent = ["excellent", "superb", "great", "amazing", "good", "reliable"]
vocab_poor = ["terrible", "bad", "broken", "awful", "poor", "unreliable"]
vocab_neutral = ["okay", "average", "mediocre", "standard", "normal", "acceptable"]

for pid in products:
    if pid % 3 == 0:
        quality = "good"
        base_rating = 4.5
        vocab = vocab_excellent + vocab_neutral
    elif pid % 3 == 1:
        quality = "bad"
        base_rating = 2.0
        vocab = vocab_poor + vocab_neutral
    else:
        quality = "neutral"
        base_rating = 3.5
        vocab = vocab_neutral

    num_reviews = np.random.randint(1, 6)
    for _ in range(num_reviews):
        words = np.random.choice(vocab, size=np.random.randint(3, 8), replace=True)
        text = " ".join(words) + "."

        rating = np.clip(np.random.normal(base_rating, 0.8), 1, 5)
        rating_int = int(round(rating))

        if np.random.rand() < 0.1:
            rating_str = ""
        else:
            rating_str = str(rating_int)

        data.append([str(pid), text, rating_str])

data.append(["101", "unique word alpha beta gamma.", "5"])
data.append(["120", "unique word alpha.", "4"])
data.append(["135", "unique word beta.", "4"])
data.append(["140", "unique word alpha beta.", "5"])
data.append(["145", "unique word gamma delta.", "3"])

df = pd.DataFrame(data, columns=["product_id", "review_text", "rating"])
df.to_csv("/home/user/reviews.csv", index=False)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
