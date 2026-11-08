#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_posterior_output():
    csv_path = "/home/user/measurements.csv"
    assert os.path.isfile(csv_path), f"Input file {csv_path} is missing."

    # Step 1: Read data and calculate D
    D = []
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            sensor_a = float(row["SensorA"])
            sensor_b = float(row["SensorB"])
            D.append(sensor_a - sensor_b)

    N = len(D)
    assert N > 0, "No data found in measurements.csv"

    # Step 2: Bootstrap sampling with custom LCG
    seed = 42
    def my_rand():
        nonlocal seed
        seed = (1103515245 * seed + 12345) % 2147483648
        return seed

    bootstrap_means = []
    for _ in range(10000):
        sample_sum = 0.0
        for _ in range(N):
            idx = my_rand() % N
            sample_sum += D[idx]
        bootstrap_means.append(sample_sum / N)

    D_boot = sum(bootstrap_means) / 10000.0

    # Step 3: Bayesian Inference
    mu_0 = 0.0
    var_0 = 1.0
    var = 4.0
    n = N

    posterior_mean = ((1.0 / var_0) * mu_0 + (n / var) * D_boot) / ((1.0 / var_0) + (n / var))
    expected_output = f"{posterior_mean:.4f}"

    # Step 4: Validate output file
    output_path = "/home/user/posterior.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} was not created."

    with open(output_path, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, (
        f"Incorrect value in {output_path}. "
        f"Expected '{expected_output}', but got '{actual_output}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
