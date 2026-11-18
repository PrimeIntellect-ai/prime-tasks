#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np

np.random.seed(42)
texts = ["This is document number " + str(i) + " with some random words " + ("foo bar" if i%2==0 else "baz qux") for i in range(500)]
labels = [0 if i%2==0 else 1 for i in range(500)]

df = pd.DataFrame({'text': texts, 'label': labels})
df.to_csv('/home/user/data.csv', index=False)

buggy_code = """import pandas as pd
import json
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score

def run_pipeline():
    # Load data
    df = pd.read_csv('/home/user/data.csv')
    X = df['text']
    y = df['label']

    # Generate embeddings
    vectorizer = TfidfVectorizer(max_features=100)
    X_vec = vectorizer.fit_transform(X).toarray()

    # Dimensionality reduction
    pca = PCA(n_components=10, random_state=42)
    X_pca = pca.fit_transform(X_vec)

    # Split data (DATA LEAKAGE HERE!)
    X_train, X_test, y_train, y_test = train_test_split(X_pca, y, test_size=0.3, random_state=42)

    # Train model
    clf = LogisticRegression(random_state=42)
    clf.fit(X_train, y_train)

    # Predict
    preds = clf.predict(X_test)
    acc = accuracy_score(y_test, preds)
    print(f"Test Accuracy: {acc}")

if __name__ == "__main__":
    run_pipeline()
"""
with open('/home/user/etl_pipeline.py', 'w') as f:
    f.write(buggy_code)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
