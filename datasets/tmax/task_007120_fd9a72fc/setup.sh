#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn matplotlib

    mkdir -p /home/user/data
    mkdir -p /home/user/scripts
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/dataset_A.csv
id,feature1,feature2
1,0.5,1.2
2,0.6,1.4
3,0.9,1.1
4,1.2,0.8
5,1.5,0.5
6,1.1,0.9
7,0.8,1.3
8,0.4,1.5
9,1.6,0.4
10,1.3,0.7
EOF

    cat << 'EOF' > /home/user/data/dataset_B.csv
id,feature3,target
1,3.3,10.1
2,3.4,10.5
3,3.1,11.2
4,2.8,12.0
5,2.5,13.1
6,2.9,11.8
7,3.2,10.8
8,3.5,9.9
9,2.4,13.5
10,2.7,12.4
EOF

    cat << 'EOF' > /home/user/scripts/analyze.py
import sys
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from sklearn.decomposition import PCA
from sklearn.linear_model import Ridge
from sklearn.model_selection import train_test_split

if len(sys.argv) < 2:
    print("Usage: python analyze.py <joined_csv>")
    sys.exit(1)

df = pd.read_csv(sys.argv[1])
X = df[['feature1', 'feature2', 'feature3']]
y = df['target']

# Bug 1: No random state for PCA (though PCA is deterministic for distinct eigenvalues, Ridge/train_test_split aren't)
# Bug 2: train_test_split without random_state makes regression non-deterministic
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)

pca = PCA(n_components=1)
X_train_pca = pca.fit_transform(X_train)
X_test_pca = pca.transform(X_test)

model = Ridge()
model.fit(X_train_pca, y_train)
score = model.score(X_test_pca, y_test)

print(f"PCA_Var: {pca.explained_variance_ratio_[0]:.4f}")
print(f"R2: {score:.4f}")

# Generate correlation matrix
corr = df.corr()
fig, ax = plt.subplots()
cax = ax.matshow(corr, cmap='coolwarm')
fig.colorbar(cax)
plt.xticks(range(len(corr.columns)), corr.columns, rotation=90)
plt.yticks(range(len(corr.columns)), corr.columns)

# Bug 3: Tries to show plot interactively, will fail in headless without X11
plt.show()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
