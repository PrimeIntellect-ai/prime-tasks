#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    cat << 'EOF' > /tmp/verify.py
import numpy as np
from scipy.optimize import root
from scipy.stats import wasserstein_distance
from scipy.special import softmax
import sys
import os

target = np.array([0.1, 0.2, 0.3, 0.2, 0.2])
states = np.arange(5)

def solve_y(a, b):
    def equations(y):
        eqs = np.zeros(5)
        for i in range(5):
            eqs[i] = y[i] - a * np.sin(y[(i+1)%5]) - b * np.cos(y[(i-1)%5]) - i/10.0
        return eqs
    sol = root(equations, np.zeros(5), method='lm')
    return sol.x

def objective(a, b):
    y = solve_y(a, b)
    p = softmax(y)
    return wasserstein_distance(states, states, p, target)

# Baseline optimization to find the minimum distance
from scipy.optimize import minimize
def obj_wrap(params):
    return objective(params[0], params[1])

res = minimize(obj_wrap, [0.0, 0.0], bounds=[(-2, 2), (-2, 2)])
expected_min = res.fun

if not os.path.exists('/home/user/result.txt'):
    print("result.txt not found")
    sys.exit(1)

with open('/home/user/result.txt', 'r') as f:
    text = f.read().strip()

try:
    a_str, b_str = text.split(',')
    a_val = float(a_str)
    b_val = float(b_str)
except Exception as e:
    print(f"Failed to parse result.txt: {e}")
    sys.exit(1)

dist = objective(a_val, b_val)

# The distance should be close to the optimal
if dist <= expected_min + 0.05:
    print("Success")
    sys.exit(0)
else:
    print(f"Distance {dist} is too far from optimal {expected_min}")
    sys.exit(1)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
