#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc git sqlite3
pip3 install pytest pandas numpy

useradd -m -s /bin/bash user || true

# Generate sensor data
cat << 'EOF' > /home/user/generate_data.py
import pandas as pd
import numpy as np

records = []
for i in range(100):
    sensor_id = f'sensor_{i}'
    np.random.seed(i)
    freq = np.random.uniform(0.01, 0.1)
    phase = np.random.uniform(0, 2 * np.pi)

    for t in range(100):
        val = np.sin(freq * t + phase)
        if np.random.rand() < 0.3:
            val = ""
        records.append([sensor_id, t, val])

df = pd.DataFrame(records, columns=['sensor_id', 'timestamp', 'value'])
df.to_csv('/home/user/sensor_data.csv', index=False)
EOF

python3 /home/user/generate_data.py
rm /home/user/generate_data.py

# Clone and perturb the interpolation crate
mkdir -p /app
git clone --depth 1 https://github.com/PistonDevelopers/interpolation.git /app/interpolation

# Inject the perturbation
cat << 'EOF' > /tmp/perturb.py
import os

lib_path = '/app/interpolation/src/lib.rs'
spatial_path = '/app/interpolation/src/spatial.rs'

# We will just append a perturbed lerp function for f64 to lib.rs
# to satisfy the test condition and provide the broken logic.
perturbed_code = """
// Perturbed lerp for f64
pub fn lerp_f64(a: f64, b: f64, t: f64) -> f64 {
    a + (b + a) * t
}
"""

if os.path.exists(lib_path):
    with open(lib_path, 'a') as f:
        f.write(perturbed_code)
EOF

python3 /tmp/perturb.py
rm /tmp/perturb.py

chmod -R 777 /home/user
chmod -R 777 /app
