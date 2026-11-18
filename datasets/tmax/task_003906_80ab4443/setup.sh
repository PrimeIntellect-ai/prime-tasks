#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/texts.csv
id,text
1,The quick brown fox
2,Jumps over the lazy dog
3,Data engineering is fun
4,Machine learning is cool
5,Silent type conversions cause bugs
6,Embeddings represent text
EOF

    cat << 'EOF' > /home/user/labels.csv
id,label
1,0
2,0
4,1
5,2
6,1
EOF

    cat << 'EOF' > /home/user/etl_pipeline.py
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
import json

def main():
    # Load data
    texts = pd.read_csv('/home/user/texts.csv')
    labels = pd.read_csv('/home/user/labels.csv')

    # Merge data - BUG: left join causes id=3 to have a NaN label, turning the column float64
    df = texts.merge(labels, on='id', how='left')

    # Compute embeddings
    vectorizer = TfidfVectorizer()
    X = vectorizer.fit_transform(df['text'])

    # Target variable
    y = df['label']

    # Train model
    model = LogisticRegression(random_state=42)
    model.fit(X, y) # Crashes here due to NaN

    # Evaluate
    preds = model.predict(X)
    acc = accuracy_score(y, preds)

    # Track experiment
    with open('/home/user/metrics.json', 'w') as f:
        json.dump({"accuracy": acc}, f)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
