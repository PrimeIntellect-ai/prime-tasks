#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip make
pip3 install pytest pandas numpy scikit-learn matplotlib

mkdir -p /home/user/dataset
mkdir -p /home/user/scripts
mkdir -p /home/user/results

cat << 'EOF' > /home/user/setup_data.py
import pandas as pd
import numpy as np

np.random.seed(42)
n_rows = 1000
sensor_types = np.random.choice(['Type_A', 'Type_B', 'Type_C', 'Type_D', 'Type_E'], size=n_rows)
data = {'sensor_type': sensor_types}

for i in range(1, 21):
    # Add some correlation based on sensor type to make PCA meaningful
    base = np.where(sensor_types == 'Type_A', 10,
           np.where(sensor_types == 'Type_B', 20,
           np.where(sensor_types == 'Type_C', 30,
           np.where(sensor_types == 'Type_D', 40, 50))))
    data[f'reading_{i}'] = base + np.random.normal(0, 5, size=n_rows)

df = pd.DataFrame(data)
df.to_csv('/home/user/dataset/sensors.csv', index=False)
EOF

python3 /home/user/setup_data.py

cat << 'EOF' > /home/user/scripts/pca_plot.py
import pandas as pd
from sklearn.decomposition import PCA
import matplotlib.pyplot as plt

# Bad configuration causing blank plot in headless
plt.ion()

df = pd.read_csv('/home/user/dataset/aggregated.csv')
features = [c for c in df.columns if c != 'sensor_type']

pca = PCA(n_components=2)
components = pca.fit_transform(df[features])

plt.figure()
plt.scatter(components[:, 0], components[:, 1])
# Missing plt.savefig, or bad backend
with open('/home/user/results/pca_plot.png', 'w') as f:
    f.write('') # Emulates the empty file bug
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
