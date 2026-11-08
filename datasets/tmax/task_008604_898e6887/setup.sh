#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user
    cat << 'EOF' > /home/user/run_pipeline.py
import numpy as np
import json

def get_primer(sequence):
    # Extracts first 10 bases
    subseq = sequence[:10]
    # BUG: Just reverses the sequence, does not complement
    return subseq[::-1]

def run_mcmc():
    np.random.seed(42)
    samples = np.zeros((5000, 2))
    current = np.array([1.5, -0.5])

    # Toy MCMC loop
    for i in range(5000):
        proposal = current + np.random.normal(0, 0.1, 2)
        # Dummy acceptance rule for illustration
        if np.random.rand() < 0.8:
            current = proposal
        samples[i] = current

    # BUG: np.cov defaults to rowvar=True, producing a 5000x5000 matrix
    cov_matrix = np.cov(samples)
    return cov_matrix.tolist()

def regression_test(primer, cov_matrix):
    expected_primer = "TCGATCGCAT"
    if primer != expected_primer:
        raise ValueError(f"Regression failed: Primer '{primer}' != '{expected_primer}'")

    cov_np = np.array(cov_matrix)
    if cov_np.shape != (2, 2):
        raise ValueError(f"Regression failed: Covariance matrix has wrong shape {cov_np.shape}, expected (2, 2)")

    print("Regression passed!")

if __name__ == "__main__":
    target_sequence = "ATGCGATCGATCGATCGATCG"
    primer = get_primer(target_sequence)
    cov = run_mcmc()

    regression_test(primer, cov)

    with open("/home/user/results.json", "w") as f:
        json.dump({"primer": primer, "covariance": cov}, f, indent=4)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
