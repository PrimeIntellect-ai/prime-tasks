#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scikit-learn

    useradd -m -s /bin/bash user || true

    # Create raw_data.csv
    cat << 'EOF' > /home/user/create_data.py
import pandas as pd
from sklearn.datasets import make_classification

X, y = make_classification(n_samples=1000, n_features=2, n_redundant=0, n_informative=2, random_state=10, weights=[0.7, 0.3])
df = pd.DataFrame(X, columns=['feature1', 'feature2'])
df['target'] = y
df.to_csv('/home/user/raw_data.csv', index=False)
EOF

    python3 /home/user/create_data.py
    rm /home/user/create_data.py

    # Create buggy pipeline.py
    cat << 'EOF' > /home/user/pipeline.py
import pandas as pd
import sys
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.naive_bayes import GaussianNB
from sklearn.metrics import accuracy_score

if len(sys.argv) != 2:
    print("Usage: python pipeline.py <seed>")
    sys.exit(1)

seed = int(sys.argv[1])

df = pd.read_csv('/home/user/raw_data.csv')
X = df[['feature1', 'feature2']]
y = df['target']

# BUG: Data leakage
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.2, random_state=seed)

clf = GaussianNB()
clf.fit(X_train, y_train)

y_pred = clf.predict(X_test)
acc = accuracy_score(y_test, y_pred)

print(f"Accuracy: {acc:.4f}")
print(f"Class 1 Prior: {clf.class_prior_[1]:.4f}")
EOF

    chmod -R 777 /home/user
