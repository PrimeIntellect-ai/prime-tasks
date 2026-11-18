#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --no-cache-dir pytest pandas numpy scikit-learn scipy mlflow

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
words = ["analysis", "data", "science", "machine", "learning", "model", "prediction", "leakage", "cloud", "pipeline", "statistics", "python"]
data = []
for _ in range(500):
    text = " ".join(np.random.choice(words, size=np.random.randint(5, 15)))
    label = np.random.randint(0, 2)
    data.append({"text": text, "label": label})

df = pd.DataFrame(data)
df.to_csv("dataset.csv", index=False)
EOF
    python3 generate_data.py
    rm generate_data.py

    cat << 'EOF' > train_pipeline.py
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.decomposition import TruncatedSVD
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
import mlflow
import numpy as np

# Load
df = pd.read_csv("dataset.csv")

# Embedding & Dim Reduction (LEAKAGE HERE)
vectorizer = TfidfVectorizer(max_features=1000)
X_emb = vectorizer.fit_transform(df['text'])
svd = TruncatedSVD(n_components=10, random_state=42)
X_reduced = svd.fit_transform(X_emb)

# Split
X_train, X_test, y_train, y_test = train_test_split(X_reduced, df['label'], test_size=0.2, random_state=42)

# Train
clf = RandomForestClassifier(random_state=42)
clf.fit(X_train, y_train)
acc = clf.score(X_test, y_test)

# Log
mlflow.set_experiment("text_classification")
with mlflow.start_run():
    mlflow.log_metric("accuracy", acc)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
