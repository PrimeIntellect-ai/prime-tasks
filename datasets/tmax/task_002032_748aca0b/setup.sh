#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas matplotlib numpy

mkdir -p /home/user
cd /home/user

cat << 'EOF' > sensor_A.csv
time,temp,pressure
1,20.5,1000.0
2,21.0,1005.0
3,21.5,1002.0
4,22.0,998.0
5,22.5,995.0
6,23.0,990.0
EOF

cat << 'EOF' > sensor_B.csv
timestamp,humidity,vibration
1,45.0,0.1
2,N/A,0.2
3,46.0,0.15
4,46.5,0.1
5,47.0,0.3
6,48.0,0.25
EOF

cat << 'EOF' > sensor_C.csv
time,light
1,100
3,110
4,105
5,120
6,130
EOF

cat << 'EOF' > run_analysis.py
import pandas as pd
import matplotlib.pyplot as plt

# 1. Load data
df_a = pd.read_csv('sensor_A.csv')
df_b = pd.read_csv('sensor_B.csv')
df_c = pd.read_csv('sensor_C.csv')

# 2. Join data
# BUG: df_b uses 'timestamp' instead of 'time'
df_merged = df_a.merge(df_b, on='time').merge(df_c, on='time')

# 3. Clean data & Schema enforcement
# BUG: Doesn't handle 'N/A' properly, leaving it as object

# 4. Math: Correlation
corr = df_merged[['temp', 'pressure', 'humidity', 'vibration', 'light']].corr()
corr.to_csv('correlation_matrix.csv')

# 5. Plotting
plt.matshow(corr)
plt.show() # BUG: In headless environment this blocks or does nothing
plt.savefig('heatmap.png') # BUG: saves blank after show()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
