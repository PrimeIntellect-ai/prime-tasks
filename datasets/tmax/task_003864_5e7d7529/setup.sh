#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
texts = []
labels = []
for i in range(1000):
    if i % 2 == 0:
        texts.append(f"this is a very positive and great text {np.random.randint(100)} awesome good")
        labels.append(1)
    else:
        texts.append(f"this is a highly negative and bad text {np.random.randint(100)} terrible awful")
        labels.append(0)

df = pd.DataFrame({'text': texts, 'label': labels})
# Add some noise
noise_idx = np.random.choice(1000, 100, replace=False)
df.loc[noise_idx, 'label'] = 1 - df.loc[noise_idx, 'label']

df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /home/user/generate_data.py

    cat << 'EOF' > /home/user/train_model.py
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score

df = pd.read_csv('/home/user/data.csv')
X = df['text']
y = df['label']

# Data leak: transforming before splitting
vectorizer = TfidfVectorizer()
X_vec = vectorizer.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_vec, y, test_size=0.2, random_state=42)

model = LogisticRegression(random_state=42)
model.fit(X_train, y_train)

preds = model.predict(X_test)
acc = accuracy_score(y_test, preds)
print(f"Accuracy: {acc}")
EOF

    chmod -R 777 /home/user
