#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
vocab_a = ["apple", "banana", "cherry", "date", "elderberry"]
vocab_b = ["car", "bus", "train", "plane", "boat"]

data = []
for _ in range(300):
    if np.random.rand() > 0.5:
        text = " ".join(np.random.choice(vocab_a, size=10))
        label = 0
    else:
        text = " ".join(np.random.choice(vocab_b, size=10))
        label = 1
    data.append([text, label])

df = pd.DataFrame(data, columns=["text", "label"])
df.to_csv("/home/user/data.csv", index=False)
EOF

    python3 /home/user/setup_data.py
    rm /home/user/setup_data.py

    cat << 'EOF' > /home/user/train_model.py
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.neighbors import KNeighborsClassifier
from sklearn.model_selection import GridSearchCV, train_test_split

# 1. ETL
df = pd.read_csv('/home/user/data.csv')
X = df['text']
y = df['label']

# 2. Embedding (Data Leakage!)
vectorizer = TfidfVectorizer()
X_vec = vectorizer.fit_transform(X)

# 3. Split
X_train, X_test, y_train, y_test = train_test_split(X_vec, y, test_size=0.2, random_state=42)

# 4. Hyperparameter tuning & Cross-validation
param_grid = {'n_neighbors': [3, 5, 7]}
grid = GridSearchCV(KNeighborsClassifier(), param_grid, cv=5)
grid.fit(X_train, y_train)

# 5. Output result
score = grid.score(X_test, y_test)
with open('/home/user/result.txt', 'w') as f:
    f.write(f"Test Score: {score:.4f}\n")
    f.write(f"Best Params: {grid.best_params_}\n")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
