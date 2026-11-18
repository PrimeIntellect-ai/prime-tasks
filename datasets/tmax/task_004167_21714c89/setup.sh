#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/reference_yield.csv
time,yield
0,2.0
1,4.52
2,9.88
3,20.42
4,39.04
5,67.06
6,97.74
7,113.11
8,118.06
9,119.34
10,119.76
11,119.91
12,119.97
13,119.99
14,120.0
15,120.0
16,120.0
17,120.0
18,120.0
19,120.0
20,120.0
21,120.0
22,120.0
23,120.0
24,120.0
25,120.0
26,120.0
27,120.0
28,120.0
29,120.0
30,120.0
EOF

    cat << 'EOF' > /home/user/pcr_model.py
import numpy as np
import sys

def simulate_pcr(r, K, t_eval):
    """
    Simulates the PCR logistic growth.
    dY/dt = r * Y * (1 - Y/K)
    Y(0) = 2.0
    """
    dt = 5.0 # BUG: dt is too large, causes divergence
    # Interpolation array
    y_out = []

    for t_target in t_eval:
        times = np.arange(0, t_target + dt, dt)
        y = np.zeros(len(times))
        y[0] = 2.0
        for i in range(1, len(times)):
            y[i] = y[i-1] + dt * r * y[i-1] * (1 - y[i-1] / K)

        # very crude nearest neighbor for the buggy version
        y_out.append(y[-1])

    return np.array(y_out)

def test_regression():
    # True values for the regression test
    r_test = 0.5
    K_test = 100.0
    t_eval = np.arange(0, 20, 1)

    y_sim = simulate_pcr(r_test, K_test, t_eval)

    # Analytic solution for Y(0)=2.0, r=0.5, K=100
    y_analytic = (100.0 * 2.0 * np.exp(0.5 * t_eval)) / (100.0 + 2.0 * (np.exp(0.5 * t_eval) - 1))

    mse = np.mean((y_sim - y_analytic)**2)
    if mse < 1.0:
        print("Test passed!")
        sys.exit(0)
    else:
        print(f"Test failed! MSE: {mse}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == '--test':
        test_regression()
EOF

    cat << 'EOF' > /home/user/gene_sequence.txt
ATGCGTACGTAGCTAGCTAGCATCGATCGATCGATCGATCGTACGATCGTACG
EOF

    cat << 'EOF' > /home/user/candidates.fasta
>primer1
ATGCGTAC
>primer2
GCTAGCATCGATCGATC
>primer3
CGTACGATCGTACGAAA
>primer4
GCTAGCATCGATCGA
EOF

    chmod -R 777 /home/user
