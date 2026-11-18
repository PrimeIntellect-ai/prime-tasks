#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np

def simulate_heat():
    alpha = 0.01
    L = 1.0
    T = 0.5

    # Buggy parameters:
    Nx = 10
    dt = 0.1

    dx = L / (Nx - 1)
    x = np.linspace(0, L, Nx)

    # Initial condition
    u = np.sin(np.pi * x)

    t = 0
    while t < T:
        u_new = np.copy(u)
        for i in range(1, Nx - 1):
            u_new[i] = u[i] + alpha * dt / dx**2 * (u[i+1] - 2*u[i] + u[i-1])
        u = u_new
        t += dt

    np.save('/home/user/simulated_profile.npy', u)

if __name__ == "__main__":
    simulate_heat()
EOF

    cat << 'EOF' > /home/user/generate_obs.py
import numpy as np
import pandas as pd

# Generate exact expected grid
Nx = 50
x = np.linspace(0, 1, Nx)

# Analytical-ish approximation for t=0.5, alpha=0.01
# u(x,t) = exp(-alpha * pi^2 * t) * sin(pi * x)
u_true = np.exp(-0.01 * np.pi**2 * 0.5) * np.sin(np.pi * x)

# Add tiny noise
np.random.seed(42)
u_obs = u_true + np.random.normal(0, 0.01, Nx)

df = pd.DataFrame({
    'id': np.arange(Nx),
    'raw_x': x,
    'raw_temp': u_obs
})

# Shuffle the dataframe
df = df.sample(frac=1, random_state=42).reset_index(drop=True)
df.to_csv('/home/user/obs_data.csv', index=False)
EOF

    python3 /home/user/generate_obs.py
    rm /home/user/generate_obs.py

    chmod -R 777 /home/user
