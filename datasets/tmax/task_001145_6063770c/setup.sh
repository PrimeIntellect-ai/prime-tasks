#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest numpy scikit-learn

    mkdir -p /home/user
    cd /home/user

    # Create smooth.c
    cat << 'EOF' > /home/user/smooth.c
void smooth(double* input, double* output, int n) {
    if (n == 0) return;
    output[0] = input[0];
    for(int i = 1; i < n - 1; i++) {
        output[i] = (input[i-1] + input[i] + input[i+1]) / 3.0;
    }
    if (n > 1) {
        output[n-1] = input[n-1];
    }
}
EOF

    # Create python script to generate spectra.csv
    cat << 'EOF' > /home/user/gen_data.py
import numpy as np

np.random.seed(42)
n_samples = 100
n_features = 200

base_spectrum = np.exp(-((np.linspace(0, 10, n_features) - 5)**2) / 2)
X = np.zeros((n_samples, n_features))
for i in range(n_samples):
    X[i, :] = base_spectrum * (1 + 0.01 * np.random.randn(n_features)) + 0.05 * np.random.randn(n_features)

X = np.abs(X)
np.savetxt('/home/user/spectra.csv', X, delimiter=',')
EOF

    # Generate data
    python3 /home/user/gen_data.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
