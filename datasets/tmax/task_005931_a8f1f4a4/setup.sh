#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest numpy

mkdir -p /home/user/data

cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)

# Generate weights
W = np.array([
    [1.0, 0.5, 0.0, -0.1],
    [0.0, 1.0, -0.5, 0.2],
    [0.1, 0.0, 1.0, 0.0],
    [0.0, 0.0, 0.0, 1.0]
])
np.savetxt('/home/user/data/weights.csv', W, delimiter=',', fmt='%.4f')

# Generate Target
target = np.array([0.5, 1.0, -0.5, 0.2])
np.savetxt('/home/user/data/target.csv', target.reshape(1, 4), delimiter=',', fmt='%.4f')

# Generate Items
np.random.seed(42)
item_ids = np.arange(1, 101)
item_features = np.random.randn(100, 4)

items_data = np.column_stack((item_ids, item_features))
np.savetxt('/home/user/data/items.csv', items_data, delimiter=',', fmt='%d,%.4f,%.4f,%.4f,%.4f')

# Compute Ground Truth
target_transformed = W @ target

similarities = []
for row in items_data:
    i_id = int(row[0])
    i_feat = row[1:]
    i_transformed = W @ i_feat

    # Cosine similarity
    dot = np.dot(target_transformed, i_transformed)
    norm_t = np.linalg.norm(target_transformed)
    norm_i = np.linalg.norm(i_transformed)

    if norm_t == 0 or norm_i == 0:
        sim = 0
    else:
        sim = dot / (norm_t * norm_i)

    similarities.append((sim, i_id))

similarities.sort(key=lambda x: x[0], reverse=True)
top_3 = similarities[:3]

with open('/home/user/expected_recommendations.txt', 'w') as f:
    for sim, i_id in top_3:
        f.write(f"{i_id}\n")
EOF

python3 /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
