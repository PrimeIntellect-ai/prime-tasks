#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy

mkdir -p /home/user

cat << 'EOF' > /home/user/setup.py
import os
import pandas as pd
import numpy as np

data = {
    'temperature': [20.0, 21.0, np.nan, 22.0, 100.0, 19.5, 20.5, "ERROR", 21.5, 20.2],
    'pressure': [101.3, 101.5, 101.2, np.nan, 500.0, 101.0, 101.4, 101.3, 101.6, 101.1],
    'vibration': [4.5, 5.2, 4.8, 5.5, 50.0, 4.9, 5.1, 4.7, 5.3, 4.6]
}

df = pd.DataFrame(data)
os.makedirs('/home/user', exist_ok=True)
df.to_csv('/home/user/sensor_data.csv', index=False)

with open('/home/user/analyze.py', 'w') as f:
    f.write('''import pandas as pd
import matplotlib.pyplot as plt
# Broken script
df = pd.read_csv("sensor_data.csv")
plt.hist(df["vibration"])
plt.show() # This will fail in headless
''')
EOF

python3 /home/user/setup.py
rm /home/user/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
