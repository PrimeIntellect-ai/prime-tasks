#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    pip3 install numpy scipy nbformat nbconvert ipykernel

    mkdir -p /home/user/sim_project
    cd /home/user/sim_project

    cat << 'EOF' > optimizer.py
import numpy as np

def gauss_newton(X, y, initial_guess, max_iter=50, tol=1e-5):
    beta = np.array(initial_guess, dtype=float)
    for i in range(max_iter):
        # Model: y = beta[0]*X[:,0] + beta[1]*X[:,1] + beta[2]*(X[:,0]**2)
        y_pred = beta[0] * X[:, 0] + beta[1] * X[:, 1] + beta[2] * (X[:, 0]**2)

        # Jacobian matrix
        J = np.column_stack([
            X[:, 0],
            X[:, 1],
            X[:, 0]**2
        ])

        r = y - y_pred

        JTJ = J.T @ J
        JTr = J.T @ r

        # This standard inversion fails due to collinearity
        delta = np.linalg.inv(JTJ) @ JTr

        beta += delta
        if np.linalg.norm(delta) < tol:
            break
    return beta
EOF

    cat << 'EOF' > create_notebook.py
import nbformat as nbf

nb = nbf.v4.new_notebook()

code_1 = """\
import numpy as np
from optimizer import gauss_newton

np.random.seed(42)
N = 100
# Create collinear features (near-singular)
X0 = np.linspace(0, 10, N)
X1 = X0 + np.random.normal(0, 1e-10, size=N)

X = np.column_stack([X0, X1])

# True parameters: beta = [1.5, 0.0, 0.5]
y_true = 1.5 * X[:, 0] + 0.5 * (X[:, 0]**2)
y = y_true + np.random.normal(0, 0.1, size=N)

# Initial guess
beta_init = [0.1, 0.1, 0.1]

# Run optimizer
beta_opt = gauss_newton(X, y, beta_init)

# Save results
np.savetxt("results.csv", beta_opt.reshape(1, -1), delimiter=",", fmt="%.6f")
print("Optimization successful. Results saved to results.csv")
"""

nb['cells'] = [nbf.v4.new_code_cell(code_1)]

with open('simulation.ipynb', 'w') as f:
    nbf.write(nb, f)
EOF

    python3 create_notebook.py
    rm create_notebook.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
