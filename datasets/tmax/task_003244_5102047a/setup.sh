#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip python3-numpy python3-scipy python3-setuptools
pip3 install pytest

# Create directories
mkdir -p /home/user/data
mkdir -p /app/fastvecsearch/fastvecsearch

# Create setup script for data and package
cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(0)
anchors = np.random.randn(500, 128)
anchors /= np.linalg.norm(anchors, axis=1, keepdims=True)
candidates = np.random.randn(20000, 128)
candidates /= np.linalg.norm(candidates, axis=1, keepdims=True)
np.save('/home/user/data/anchors.npy', anchors)
np.save('/home/user/data/candidates.npy', candidates)

# Create the broken package
os.makedirs('/app/fastvecsearch/fastvecsearch', exist_ok=True)
with open('/app/fastvecsearch/setup.py', 'w') as f:
    f.write('''from setuptools import setup, find_packages\nsetup(name="fastvecsearch", version="1.0.0", packages=find_packages())''')
with open('/app/fastvecsearch/fastvecsearch/__init__.py', 'w') as f:
    f.write('from .distance import cosine_sim\n')
with open('/app/fastvecsearch/fastvecsearch/distance.py', 'w') as f:
    f.write('''import numpy as np\ndef cosine_sim(a, b):\n    # Buggy implementation\n    return np.dot(a, b) / (np.linalg.norm(a) * np.linalg.nomr(b))\n''')
EOF

python3 /tmp/setup.py

# Create verifier script
cat << 'EOF' > /verify.py
import json
import numpy as np
import scipy.stats as stats

# Check package is installed and importable
try:
    import fastvecsearch
    assert hasattr(fastvecsearch, 'cosine_sim')
    # Test the fixed code
    fastvecsearch.cosine_sim(np.array([1,0]), np.array([0,1]))
except Exception as e:
    print(f"Package fastvecsearch not fixed or installed properly: {e}")
    exit(1)

with open('/home/user/hard_negatives.json', 'r') as f:
    data = json.load(f)

agent_indices = np.array(data["hard_negative_indices"])
anchors = np.load('/home/user/data/anchors.npy')
candidates = np.load('/home/user/data/candidates.npy')

# Compute ground truth
sims = anchors @ candidates.T
gt_indices = np.argsort(-sims, axis=1)[:, :5]

# Calculate overlap metric
overlaps = []
for i in range(500):
    overlaps.append(len(set(agent_indices[i]) & set(gt_indices[i])) / 5.0)
mean_overlap = np.mean(overlaps)

# Calculate ground truth stats
np.random.seed(42)
gt_hard_means = np.mean(np.take_along_axis(sims, gt_indices, axis=1), axis=1)
random_indices = np.random.choice(candidates.shape[0], size=(500, 5))
gt_rand_means = np.mean(np.take_along_axis(sims, random_indices, axis=1), axis=1)

diff = gt_hard_means - gt_rand_means
res = stats.ttest_rel(gt_hard_means, gt_rand_means)
ci = res.confidence_interval(confidence_level=0.95)

# Verify
if mean_overlap < 0.98:
    print(f"Overlap too low: {mean_overlap}")
    exit(1)

if abs(data['ttest_p_value'] - res.pvalue) > 1e-4:
    print(f"p-value mismatch. Expected {res.pvalue}, got {data['ttest_p_value']}")
    exit(1)

if abs(data['ci_lower'] - ci.low) > 1e-4 or abs(data['ci_upper'] - ci.high) > 1e-4:
    print(f"CI mismatch.")
    exit(1)

print("SUCCESS")
EOF

chmod +x /verify.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
