#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/primer_tool.py
import time
import json
import numpy as np
from scipy.optimize import minimize

def evaluate_primer_loss(params):
    # Simulates sequence alignment penalty based on temp and gc ratio
    temp, gc = params
    # Optimal should be temp=65.0, gc=0.5
    time.sleep(0.005) # Simulate expensive alignment calculation
    loss = (temp - 65.0)**2 + 1000 * (gc - 0.5)**2
    return loss

def optimize():
    params = np.array([50.0, 0.3])
    learning_rate = 0.001

    # SLOW CUSTOM OPTIMIZATION
    for _ in range(500):
        loss1 = evaluate_primer_loss([params[0] + 0.01, params[1]])
        loss2 = evaluate_primer_loss([params[0] - 0.01, params[1]])
        grad_t = (loss1 - loss2) / 0.02

        loss3 = evaluate_primer_loss([params[0], params[1] + 0.01])
        loss4 = evaluate_primer_loss([params[0], params[1] - 0.01])
        grad_gc = (loss3 - loss4) / 0.02

        params[0] -= learning_rate * grad_t
        params[1] -= learning_rate * grad_gc / 1000

    return params.tolist()

if __name__ == "__main__":
    result = optimize()
    print(json.dumps({"temperature": round(result[0], 2), "gc_ratio": round(result[1], 2)}))
EOF

    cat << 'EOF' > /home/user/test_primer.py
import time
import pytest
from primer_tool import optimize

def test_optimization_regression():
    start_time = time.time()
    res = optimize()
    duration = time.time() - start_time

    # Check optimization accuracy
    assert abs(res[0] - 65.0) < 0.1, f"Temperature {res[0]} is not optimal"
    assert abs(res[1] - 0.5) < 0.05, f"GC ratio {res[1]} is not optimal"

    # Check performance (Nelder-Mead should evaluate much faster than 500*4 iterations of 0.005s sleep)
    assert duration < 1.0, f"Optimization took too long: {duration}s"
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
