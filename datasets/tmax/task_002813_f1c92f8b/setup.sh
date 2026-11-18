#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak
pip3 install pytest pandas numpy scikit-learn matplotlib

mkdir -p /app/audio /app/data /app/scripts /app/.hidden

# 1. Generate the audio fixture
espeak -w /app/audio/client_request.wav "Please drop all columns that start with the prefix legacy underscore. Then, find the top one hundred users most similar to user ID seven three nine two."

# 2. Generate the dataset and truth
cat << 'EOF' > /app/.hidden/generate_data.py
import pandas as pd
import numpy as np
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.metrics.pairwise import cosine_similarity

np.random.seed(42)
n_users = 7000
user_ids = np.arange(1000, 1000 + n_users)

# Create valid features
features = np.random.randn(n_users, 40)
# Create legacy features (to be dropped)
legacy_features = np.random.randn(n_users, 15)

# Ensure the target user (7392) exists and inject some correlated users
target_idx = 7392 - 1000
# Make 120 users very similar to the target user
similar_indices = np.random.choice([i for i in range(n_users) if i != target_idx], 120, replace=False)
features[similar_indices] = features[target_idx] + np.random.randn(120, 40) * 0.1

cols = [f"feature_{i}" for i in range(40)]
legacy_cols = [f"legacy_metric_{i}" for i in range(15)]

df_features = pd.DataFrame(features, columns=cols)
df_legacy = pd.DataFrame(legacy_features, columns=legacy_cols)

df = pd.concat([pd.Series(user_ids, name='user_id'), df_features, df_legacy], axis=1)
# Shuffle columns (except user_id)
cols_to_shuffle = cols + legacy_cols
np.random.shuffle(cols_to_shuffle)
df = df[['user_id'] + cols_to_shuffle]

df.to_csv('/app/data/user_engagement.csv', index=False)

# Compute Ground Truth
X = df.drop(columns=['user_id'] + legacy_cols).values
X_scaled = StandardScaler().fit_transform(X)
pca = PCA(n_components=10, random_state=42)
X_pca = pca.fit_transform(X_scaled)

target_vec = X_pca[target_idx].reshape(1, -1)
sims = cosine_similarity(target_vec, X_pca).flatten()
sims[target_idx] = -np.inf # Exclude self

top_100_idx = np.argsort(sims)[::-1][:100]
top_100_users = df.iloc[top_100_idx]['user_id'].values

with open('/app/.hidden/truth.csv', 'w') as f:
    f.write("user_id\n")
    for uid in top_100_users:
        f.write(f"{uid}\n")
EOF
python3 /app/.hidden/generate_data.py

# 3. Create the buggy plotting script
cat << 'EOF' > /app/scripts/generate_plot.py
import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg') # Setup correctly for headless, but...
import matplotlib.pyplot as plt

# Simulate PCA loading (using random data for the dummy script)
x = np.random.randn(100)
y = np.random.randn(100)

plt.figure(figsize=(8,6))
plt.scatter(x, y, alpha=0.5)
plt.title("2D PCA Projection")
plt.xlabel("PC1")
plt.ylabel("PC2")

# BUG: Calling show() before savefig() clears the current figure in many backends/contexts, 
# or just logic error.
plt.show() 
plt.savefig('/home/user/pca_plot.png')
EOF
chmod +x /app/scripts/generate_plot.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
