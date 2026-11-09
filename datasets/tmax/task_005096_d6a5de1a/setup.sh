#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip wget tar gawk
pip3 install pytest numpy pandas scipy scikit-learn matplotlib

# Download and patch fastdtw
mkdir -p /app
cd /app
wget -q https://files.pythonhosted.org/packages/source/f/fastdtw/fastdtw-0.3.4.tar.gz
tar -xzf fastdtw-0.3.4.tar.gz
rm fastdtw-0.3.4.tar.gz

# Inject broken dependency into setup.py
gawk 'NR==1{print; print "import broken_environment_dependency_99"} NR>1' /app/fastdtw-0.3.4/setup.py > /app/fastdtw-0.3.4/setup_tmp.py
mv /app/fastdtw-0.3.4/setup_tmp.py /app/fastdtw-0.3.4/setup.py

# Create data
mkdir -p /home/user/data

cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd
import json
import os

np.random.seed(42)
data_dir = "/home/user/data"
os.makedirs(data_dir, exist_ok=True)

ground_truth = {}
t = np.linspace(0, 10, 100)

for i in range(30):
    cluster = i % 3
    shift = np.random.uniform(0, 2*np.pi)
    noise = np.random.normal(0, 0.2, 100)

    if cluster == 0:
        # Sine
        signal = np.sin(t + shift) + noise
    elif cluster == 1:
        # Square
        signal = np.sign(np.sin(t + shift)) + noise
    else:
        # Random Walk
        signal = np.cumsum(np.random.normal(0, 0.5, 100)) + noise

    df = pd.DataFrame({'time': t, 'signal': signal})
    filename = f"dataset_{i}.csv"
    df.to_csv(os.path.join(data_dir, filename), index=False)
    ground_truth[filename] = cluster

with open("/home/user/ground_truth.json", "w") as f:
    json.dump(ground_truth, f)
EOF

python3 /home/user/generate_data.py
rm /home/user/generate_data.py

cat << 'EOF' > /home/user/plot_clusters.py
import matplotlib.pyplot as plt
from scipy.cluster.hierarchy import dendrogram, linkage
import numpy as np
import json

def main():
    # Example script missing matplotlib.use('Agg')
    # The agent is expected to fix this script and feed it the distance matrix
    try:
        with open('/home/user/clusters.json', 'r') as f:
            clusters = json.load(f)
    except FileNotFoundError:
        print("clusters.json not found")
        return

    # Dummy plot to simulate dendrogram generation
    fig = plt.figure(figsize=(10, 5))
    plt.plot([1, 2, 3])
    plt.title('Dendrogram')
    plt.savefig('/home/user/dendrogram.png')

if __name__ == "__main__":
    main()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
