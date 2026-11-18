#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
words = ["good", "bad", "excellent", "terrible", "average", "okay", "great", "awful", "fantastic", "horrible"]
data = []
for i in range(200):
    sentiment = np.random.randint(0, 2)
    if sentiment == 1:
        text = " ".join(np.random.choice(words, size=5, p=[0.2, 0.05, 0.2, 0.05, 0.1, 0.1, 0.2, 0.05, 0.05, 0.0]))
    else:
        text = " ".join(np.random.choice(words, size=5, p=[0.05, 0.2, 0.05, 0.2, 0.1, 0.1, 0.05, 0.2, 0.0, 0.05]))
    data.append({"text": text, "sentiment": sentiment})

df = pd.DataFrame(data)
df.to_csv("/home/user/reviews.csv", index=False)
EOF

    python3 /tmp/generate_data.py

    cat << 'EOF' > /home/user/train.py
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GridSearchCV
import json

df = pd.read_csv('/home/user/reviews.csv')
X = df['text']
y = df['sentiment']

# BUG: Data leakage
vectorizer = TfidfVectorizer()
X_tfidf = vectorizer.fit_transform(X)

model = LogisticRegression(random_state=42)
param_grid = {'C': [0.1, 1.0]}

grid = GridSearchCV(model, param_grid, cv=3)
grid.fit(X_tfidf, y)

results = {
    "best_score": grid.best_score_,
    "best_params": grid.best_params_
}
with open('/home/user/results.json', 'w') as f:
    json.dump(results, f)
EOF

    chown -R user:user /home/user/
    chmod -R 777 /home/user
