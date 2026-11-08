#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn scipy

    mkdir -p /home/user
    mkdir -p /app/eval_corpus/clean
    mkdir -p /app/eval_corpus/evil

    # Create dummy video file
    touch /app/test_video.mp4

    # Generate synthetic train data and eval corpus
    python3 -c "
import pandas as pd
import numpy as np
import os

np.random.seed(42)

# Train data
n_samples = 1000
# Clean (label 0)
clean_X = np.random.normal(loc=0.5, scale=0.1, size=(n_samples//2, 4))
# Evil (label 1)
evil_X = np.random.normal(loc=[0.8, 0.2, 0.3, 0.9], scale=0.1, size=(n_samples//2, 4))

X = np.vstack([clean_X, evil_X])
y = np.array([0]*(n_samples//2) + [1]*(n_samples//2))

df = pd.DataFrame(X, columns=['brightness', 'contrast', 'sharpness', 'motion_corr'])
df['label'] = y
# Shuffle
df = df.sample(frac=1, random_state=42).reset_index(drop=True)
df.to_csv('/home/user/train_data.csv', index=False)

# Eval corpus - Clean
for i in range(5):
    cx = np.random.normal(loc=0.5, scale=0.1, size=(50, 4))
    cdf = pd.DataFrame(cx, columns=['brightness', 'contrast', 'sharpness', 'motion_corr'])
    cdf.to_csv(f'/app/eval_corpus/clean/clean_{i}.csv', index=False)

# Eval corpus - Evil
for i in range(5):
    ex = np.random.normal(loc=[0.8, 0.2, 0.3, 0.9], scale=0.1, size=(50, 4))
    edf = pd.DataFrame(ex, columns=['brightness', 'contrast', 'sharpness', 'motion_corr'])
    edf.to_csv(f'/app/eval_corpus/evil/evil_{i}.csv', index=False)
"

    # Create train.py with data leakage
    cat << 'EOF' > /home/user/train.py
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.decomposition import PCA
from sklearn.linear_model import LogisticRegression
import pickle

df = pd.read_csv('train_data.csv')
X = df[['brightness', 'contrast', 'sharpness', 'motion_corr']]
y = df['label']

# DANGER: Data Leakage! Fitting PCA on the entire dataset
pca = PCA(n_components=2)
X_pca = pca.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(X_pca, y, test_size=0.2, random_state=42)

clf = LogisticRegression()
clf.fit(X_train, y_train)

print(f"Accuracy: {clf.score(X_test, y_test)}")

# Save model (buggy version)
with open('model.pkl', 'wb') as f:
    pickle.dump(clf, f)
EOF

    # Create extract.py
    cat << 'EOF' > /home/user/extract.py
import sys
import pandas as pd
import numpy as np

if len(sys.argv) != 3:
    print("Usage: python extract.py <input_mp4> <output_csv>")
    sys.exit(1)

# Mock extraction: generate evil features for the test video
np.random.seed(1337)
n_frames = 60
df = pd.DataFrame({
    'brightness': np.random.normal(0.8, 0.1, n_frames),
    'contrast': np.random.normal(0.2, 0.1, n_frames),
    'sharpness': np.random.normal(0.3, 0.1, n_frames),
    'motion_corr': np.random.normal(0.9, 0.1, n_frames)
})
df.to_csv(sys.argv[2], index=False)
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
