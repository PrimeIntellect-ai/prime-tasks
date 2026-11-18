#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ml_pipeline
    python3 -m venv /home/user/venv

    cat << 'EOF' > /home/user/ml_pipeline/process_data.py
import numpy as np
import matplotlib.pyplot as plt
from sklearn.decomposition import PCA
from scipy import stats
import sys

# Generate data
group1 = np.random.randn(50, 20) + 0.5
group2 = np.random.randn(50, 20) - 0.5
data = np.vstack((group1, group2))

# Dimensionality reduction
pca = PCA(n_components=2)
reduced = pca.fit_transform(data)

# Hypothesis test on PC1
pc1_g1 = reduced[:50, 0]
pc1_g2 = reduced[50:, 0]
t_stat, p_val = stats.ttest_ind(pc1_g1, pc1_g2)

# Confidence interval for difference in means
cm = np.mean(pc1_g1) - np.mean(pc1_g2)
se = np.sqrt(np.var(pc1_g1, ddof=1)/50 + np.var(pc1_g2, ddof=1)/50)
ci_low = cm - 1.96 * se
ci_high = cm + 1.96 * se

print(f"P-VALUE: {p_val}")
print(f"CI_LOW: {ci_low}")
print(f"CI_HIGH: {ci_high}")

# Plot
plt.scatter(reduced[:, 0], reduced[:, 1])
plt.show()
EOF

    cat << 'EOF' > /home/user/ml_pipeline/run.sh
#!/bin/bash
# Broken pipeline script
python process_data.py
EOF

    chmod +x /home/user/ml_pipeline/run.sh
    chown -R user:user /home/user/ml_pipeline
    chown -R user:user /home/user/venv

    chmod -R 777 /home/user
