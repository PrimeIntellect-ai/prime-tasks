#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn

    useradd -m -s /bin/bash user || true

    # Generate data.csv
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import pandas as pd

np.random.seed(42)
n_samples = 1000
n_features = 50

X = np.random.randn(n_samples, n_features) * 10

# Inject missing values
mask = np.random.rand(n_samples, n_features) < 0.1
X[mask] = np.nan

# Inject outliers
outlier_mask = np.random.rand(n_samples, n_features) < 0.05
X[outlier_mask] = X[outlier_mask] * 100

user_ids = [f'U{i:04d}' for i in range(n_samples)]
items = ['ItemA', 'ItemB', 'ItemC', 'ItemD', 'ItemE']
# To make predictions somewhat meaningful, assign target based on an underlying pattern of features
# Clean version of X for target generation
X_clean = np.nan_to_num(X, nan=0.0)
X_clean = np.clip(X_clean, -30, 30)
weights = np.random.randn(n_features, len(items))
logits = X_clean.dot(weights)
target_idx = np.argmax(logits, axis=1)
target_items = [items[i] for i in target_idx]

df = pd.DataFrame(X, columns=[f'feat_{i}' for i in range(n_features)])
df.insert(0, 'user_id', user_ids)
df['target_item'] = target_items

df.to_csv('/home/user/data.csv', index=False)
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    # Create leaky_pipeline.py
    cat << 'EOF' > /home/user/leaky_pipeline.py
import pandas as pd
import numpy as np
from sklearn.decomposition import PCA
from sklearn.impute import SimpleImputer
from sklearn.neighbors import KNeighborsClassifier

# Load data
df = pd.read_csv('/home/user/data.csv')
X = df.drop(columns=['user_id', 'target_item'])
y = df['target_item']

# LEAKAGE: Imputing on the whole dataset
imputer = SimpleImputer(strategy='median')
X_imputed = imputer.fit_transform(X)

# LEAKAGE: Clipping on the whole dataset
p1 = np.percentile(X_imputed, 1, axis=0)
p99 = np.percentile(X_imputed, 99, axis=0)
X_clipped = np.clip(X_imputed, p1, p99)

# LEAKAGE: PCA on the whole dataset
pca = PCA(n_components=10, random_state=42)
X_pca = pca.fit_transform(X_clipped)

# Split
X_train = X_pca[:800]
y_train = y[:800]
X_test = X_pca[800:]
test_user_ids = df['user_id'].values[800:]

# Recommend
knn = KNeighborsClassifier(n_neighbors=5, metric='euclidean')
knn.fit(X_train, y_train)
preds = knn.predict(X_test)

# Save
out = pd.DataFrame({'user_id': test_user_ids, 'recommended_item': preds})
out.to_csv('/home/user/recommendations.csv', index=False)
print("Saved recommendations.")
EOF

    chmod -R 777 /home/user
