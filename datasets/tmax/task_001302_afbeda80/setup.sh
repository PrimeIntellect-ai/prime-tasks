#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas matplotlib seaborn

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_data.csv
device_id,timestamp,sensor_A,sensor_B
D1,1,0.5,0.6
D1,2,0.7,0.8
D1,3,0.9,0.9
D1,4,1.0,0.8
D2,1,0.2,0.1
D2,2,0.3,0.3
D2,3,0.1,0.2
D2,4,0.5,0.4
EOF

    cat << 'EOF' > /home/user/model_weights.json
{
  "bias": -0.5,
  "weights": [1.2, -0.8, 0.5]
}
EOF

    cat << 'EOF' > /home/user/plot_heatmap.py
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

df = pd.read_csv('/home/user/sensor_data.csv')
corr = df[['sensor_A', 'sensor_B']].corr()

plt.figure(figsize=(6, 4))
sns.heatmap(corr, annot=True, cmap='coolwarm')
plt.title("Sensor Correlation")
plt.savefig('/home/user/heatmap.png')
EOF

    chmod +x /home/user/plot_heatmap.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
