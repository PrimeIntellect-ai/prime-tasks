#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn joblib numpy

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)

categories = ['sports', 'technology', 'politics', 'entertainment']
texts = []
cats = []

# Generate synthetic text data
word_pools = {
    'sports': ['ball', 'game', 'score', 'team', 'player', 'match', 'stadium', 'goal', 'win', 'lose'],
    'technology': ['cpu', 'software', 'cloud', 'data', 'algorithm', 'app', 'device', 'network', 'screen', 'code'],
    'politics': ['election', 'vote', 'law', 'senate', 'policy', 'campaign', 'debate', 'tax', 'mayor', 'president'],
    'entertainment': ['movie', 'music', 'star', 'actor', 'film', 'song', 'album', 'stage', 'award', 'show']
}

for i in range(1000):
    cat = np.random.choice(categories)
    # create a text of 10-20 random words from the pool
    words = np.random.choice(word_pools[cat], size=np.random.randint(10, 20))
    # add some noise words
    noise = np.random.choice(['the', 'and', 'is', 'a', 'to', 'in', 'of', 'that', 'it', 'on'], size=5)
    text_words = list(words) + list(noise)
    np.random.shuffle(text_words)

    texts.append(" ".join(text_words))
    cats.append(cat)

df = pd.DataFrame({
    'id': range(1, 1001),
    'text': texts,
    'category': cats
})

df.to_csv('/home/user/data/raw_texts.csv', index=False)
EOF

    python3 /home/user/data/generate_data.py
    rm /home/user/data/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
