#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas scikit-learn

cat << 'EOF' > /tmp/setup.py
import os
import random
import csv

os.makedirs('/home/user', exist_ok=True)

random.seed(42)
sports_words = ["goal", "match", "ball", "player", "score", "team", "tournament", "champion", "kick", "run"]
tech_words = ["cpu", "memory", "data", "software", "hardware", "internet", "code", "algorithm", "network", "cloud"]
common = ["the", "and", "is", "in", "to", "it"]

data = []
for _ in range(150):
    text = " ".join(random.choices(sports_words + common, k=15)) + "!"
    data.append((text, 0))
for _ in range(150):
    text = " ".join(random.choices(tech_words + common, k=15)) + "?"
    data.append((text, 1))

random.shuffle(data)

with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["text", "label"])
    for row in data:
        writer.writerow(row)

buggy_script = """import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.decomposition import PCA
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
import json

# Load data
df = pd.read_csv('/home/user/clean_data.csv')
X = df['text']
y = df['label']

# --- DATA LEAKAGE HERE ---
vectorizer = TfidfVectorizer(max_features=50)
X_tfidf = vectorizer.fit_transform(X).toarray()

pca = PCA(n_components=10, random_state=42)
X_pca = pca.fit_transform(X_tfidf)
# -------------------------

X_train, X_test, y_train, y_test = train_test_split(X_pca, y, test_size=0.3, random_state=42)

clf = LogisticRegression(random_state=42)
clf.fit(X_train, y_train)

y_pred = clf.predict(X_test)
acc = accuracy_score(y_test, y_pred)

with open('/home/user/metrics.json', 'w') as f:
    json.dump({'accuracy': acc}, f)
"""
with open('/home/user/train_model.py', 'w') as f:
    f.write(buggy_script)
EOF

python3 /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
