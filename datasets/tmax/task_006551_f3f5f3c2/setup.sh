#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd

# Generate time array: 0 to 10 seconds, 10000 points (1000 Hz sample rate)
t = np.linspace(0, 10, 10000, endpoint=False)

# Analytical solution
x_true = np.cos(t)
v_true = -np.sin(t)

# Inject error: 25 Hz oscillation growing exponentially at rate 0.5
error_freq = 25.0
growth_rate = 0.5

error_x = 0.01 * np.exp(growth_rate * t) * np.sin(2 * np.pi * error_freq * t)
error_v = 0.01 * np.exp(growth_rate * t) * (growth_rate * np.sin(2 * np.pi * error_freq * t) + 2 * np.pi * error_freq * np.cos(2 * np.pi * error_freq * t))

# Simulated numerical output
x_num = x_true + error_x
v_num = v_true + error_v

df = pd.DataFrame({'time': t, 'position': x_num, 'velocity': v_num})
df.to_csv('/home/user/integrator_output.csv', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
