#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas scikit-learn matplotlib

mkdir -p /home/user/data
mkdir -p /home/user/output

cat << 'EOF' > /home/user/data/day1.csv
server_id,cpu_usage,memory_usage,disk_io,network_tx,network_rx
srv_01,45.2,60.1,1024,500,600
srv_02,80.5,90.2,4096,2000,2500
srv_03,15.1,30.5,256,100,150
EOF

cat << 'EOF' > /home/user/data/day2.csv
server_id,cpu_usage,memory_usage,disk_io,network_tx,network_rx
srv_01,48.1,62.0,1100,550,620
srv_02,82.0,91.0,4200,2100,2600
srv_03,14.5,31.0,240,90,140
EOF

cat << 'EOF' > /home/user/data/day3.csv
server_id,cpu_usage,memory_usage,disk_io,network_tx,network_rx
srv_01,46.0,61.5,1050,520,610
srv_02,79.5,89.5,4000,1950,2450
srv_03,16.0,30.0,260,110,160
EOF

cat << 'EOF' > /home/user/process_and_plot.py
import pandas as pd
import glob
from sklearn.decomposition import PCA
import matplotlib.pyplot as plt
import os

# 1. Load data
files = glob.glob('/home/user/data/*.csv')
dfs = [pd.read_csv(f) for f in files]
df = pd.concat(dfs)

# 2. Aggregate
df_agg = df.groupby('server_id').mean().reset_index()

# 3. Missing standardization!
features = df_agg.drop('server_id', axis=1)

# 4. Non-reproducible PCA!
pca = PCA(n_components=2)
components = pca.fit_transform(features)

df_pca = pd.DataFrame({
    'server_id': df_agg['server_id'],
    'pc1': components[:, 0],
    'pc2': components[:, 1]
})

# 5. Save CSV
os.makedirs('/home/user/output', exist_ok=True)
df_pca.to_csv('/home/user/output/pca_results.csv', index=False)

# 6. Plotting - causes crash in headless!
plt.scatter(df_pca['pc1'], df_pca['pc2'])
plt.title('PCA of Server Metrics')
plt.xlabel('PC1')
plt.ylabel('PC2')
plt.show() # Bug here
plt.savefig('/home/user/output/pca_plot.png')
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
