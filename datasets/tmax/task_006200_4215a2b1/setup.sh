#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
words = ["ai", "data", "science", "machine", "learning", "model", "python", "code", "neural", "network", "deep", "algorithm", "cloud", "server", "database"]
texts = [" ".join(np.random.choice(words, size=20)) for _ in range(200)]
labels = np.random.randint(0, 2, size=200)
df = pd.DataFrame({'text': texts, 'label': labels})
df.to_csv('/home/user/data/articles.csv', index=False)
EOF

    python3 /home/user/setup_data.py

    cat << 'EOF' > /home/user/process_data.py
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.model_selection import train_test_split
from sklearn.metrics.pairwise import cosine_similarity
import os

def main():
    df = pd.read_csv('/home/user/data/articles.csv')

    # Buggy data leakage
    vectorizer = TfidfVectorizer(max_features=100)
    X = vectorizer.fit_transform(df['text'])

    X_train, X_test, y_train, y_test = train_test_split(X, df['label'], test_size=0.2, random_state=42)

    sim = cosine_similarity(X_test, X_train)
    max_sims = sim.max(axis=1)
    avg_max_sim = max_sims.mean()

    os.makedirs('/home/user/output', exist_ok=True)
    with open('/home/user/output/metrics.txt', 'w') as f:
        f.write(f"{avg_max_sim:.4f}\n")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
