#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/setup.py
import numpy as np
np.random.seed(42)
N = 5000
w = 0.3
mu1 = -2.0
mu2 = 2.0
samples1 = np.random.normal(mu1, 1.0, int(N * w))
samples2 = np.random.normal(mu2, 1.0, N - int(N * w))
data = np.concatenate([samples1, samples2])
np.random.shuffle(data)
np.savetxt('/home/user/data.txt', data)
EOF
    python3 /home/user/setup.py
    rm /home/user/setup.py

    cat << 'EOF' > /home/user/fit_gmm.py
import numpy as np
from scipy.optimize import root

def get_moments():
    data = np.loadtxt('/home/user/data.txt')
    return np.mean(data), np.mean(data**2), np.mean(data**3)

M1, M2, M3 = get_moments()

def equations(p):
    w, mu1, mu2 = p
    eq1 = w*mu1 + (1-w)*mu2 - M1
    eq2 = w*(mu1**2 + 1) + (1-w)*(mu2**2 + 1) - M2
    eq3 = w*(mu1**3 + 3*mu1) + (1-w)*(mu2**3 + 3*mu2) - M3
    return [eq1, eq2, eq3]

if __name__ == '__main__':
    sol = root(equations, [0.5, 0.0, 0.0], method='hybr')
    print("Optimization success:", sol.success)
    print("Roots:", sol.x)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
