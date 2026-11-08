#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_baseline.py
import numpy as np
import pandas as pd
from scipy.integrate import solve_ivp

def lv(t, z, alpha, beta, delta, gamma):
    x, y = z
    return [alpha*x - beta*x*y, delta*x*y - gamma*y]

t_eval = np.linspace(0, 10, 200)
sol = solve_ivp(lv, [0, 10], [10.0, 5.0], args=(1.5, 1.0, 1.0, 3.0), t_eval=t_eval)

df = pd.DataFrame({'t': sol.t, 'x': sol.y[0], 'y': sol.y[1]})
df.to_csv('/home/user/baseline.csv', index=False)
EOF

    python3 /tmp/generate_baseline.py
    rm /tmp/generate_baseline.py

    chmod -R 777 /home/user
